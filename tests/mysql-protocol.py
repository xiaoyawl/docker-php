#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : mysql-protocol.py
# @Desc     : 仅在断网测试容器的 loopback 上模拟截断 MySQL 包，验证 mysqlnd 受控拒绝。
# @Contact  : admin@dstw.com
import json
import socket
import struct
import subprocess
import threading


def packet(payload, sequence):
    return len(payload).to_bytes(3, 'little') + bytes([sequence]) + payload


def read_packet(connection):
    def receive(length):
        result = b''
        while len(result) < length:
            part = connection.recv(length - len(result))
            if not part:
                raise EOFError
            result += part
        return result
    header = receive(4)
    return receive(int.from_bytes(header[:3], 'little'))


capabilities = 0x00088201
greeting = (b'\x0a5.7.0-audit\0' + struct.pack('<I', 1) + b'12345678\0'
    + struct.pack('<H', capabilities & 0xffff) + b'\x21\x02\x00'
    + struct.pack('<H', capabilities >> 16) + b'\x15' + bytes(10)
    + b'abcdefghijkl\0' + b'mysql_native_password\0')
ok = b'\x00\x00\x00\x02\x00\x00\x00'
eof = b'\xfe\x00\x00\x02\x00'
metadata = (b'\x03def\x04test\x01t\x01t\x05value\x05value\x0c'
    + b'\x21\x00\x64\x00\x00\x00\xfd\x00\x00\x00\x00\x00')
cases = {
    '正常协议控制': {},
    '正常空结果控制': {'empty': True, 'row': eof},
    '截断握手': {'greet': b'\x0aX'},
    '空握手': {'greet': b''},
    '认证长度编码不完整': {'auth': b'\x00\xfc\x01'},
    '认证状态字段不完整': {'auth': b'\x00\x00\x00\x02'},
    '认证切换插件名未终止': {'auth': b'\xfemysql_native_password'},
    '认证消息内容超过包尾': {'auth': ok + b'\xfc\xff\xffabc'},
    '认证消息正常控制': {'auth_control': ok + b'\x02ok', 'expected_rejection': False},
    '认证长度前缀0xff非法': {'auth': b'\x00\xff\x00\x00\x02\x00\x00\x00'},
    '切换用户响应只有标记': {'change_user': b'\x00'},
    '切换用户插件名未终止': {'change_user': b'\xfemysql_native_password'},
    '切换用户正常控制': {'change_user': ok, 'expected_rejection': False},
    '结果集附加信息超出包尾': {'header': ok + b'\xfe' + b'\xff' * 8},
    '正常PING消息控制': {'ping': ok + b'\x02ok', 'expected_rejection': False},
    'PING消息长度超过实际包': {'ping': ok + b'\x7fabc'},
    'PING消息非法ff长度前缀': {'ping': ok + b'\xff' + b'\x01' * 8},
    '元数据长度超过包尾': {'metadata': b'\xfc\xff\xffabc'},
    '元数据固定字段不完整': {'metadata': metadata[:-5]},
    '文本行长度编码不完整': {'row': b'\xfc\x01'},
    '文本行内容超过包尾': {'row': b'\x7fabc'},
    '文本行伪造NULL长度': {'row': b'\xfe' + b'\xff' * 8},
    '文本行长度前缀0xff非法': {'row': b'\xff'},
    'EOF字段不完整': {'row': b'\xfe\x00\x00'},
    '预处理响应不完整': {'prepare': True},
}
results = []
for name, changes in cases.items():
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    listener.listen(1)
    listener.settimeout(8)
    port = listener.getsockname()[1]

    def server():
        try:
            with listener.accept()[0] as connection:
                connection.settimeout(5)
                connection.sendall(packet(changes.get('greet', greeting), 0))
                if 'greet' in changes:
                    return
                read_packet(connection)
                connection.sendall(packet(changes.get('auth', changes.get('auth_control', ok)), 2))
                if 'auth' in changes:
                    return
                read_packet(connection)
                if 'ping' in changes:
                    connection.sendall(packet(changes['ping'], 1))
                    return
                if 'change_user' in changes:
                    connection.sendall(packet(changes['change_user'], 1))
                    return
                if changes.get('prepare'):
                    connection.sendall(packet(b'\x00', 1))
                    return
                if 'header' in changes:
                    connection.sendall(packet(changes['header'], 1))
                    return
                packets = (b'\x01', changes.get('metadata', metadata), eof, changes.get('row', b'\x02ok'))
                if not changes.get('empty'):
                    packets += (eof,)
                for sequence, data in enumerate(packets, 1):
                    connection.sendall(packet(data, sequence))
        except (OSError, EOFError):
            pass
        finally:
            listener.close()

    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    code = '''mysqli_report(MYSQLI_REPORT_OFF);
$db=@mysqli_connect("127.0.0.1","audit","",null,%d);
if(!$db){echo json_encode(array("rejected"=>true));exit;}
''' % port
    if 'ping' in changes:
        code += '$result=@$db->ping();echo json_encode(array("rejected"=>$result===false,"error"=>$db->errno));'
    elif 'change_user' in changes:
        code += '$result=@$db->change_user("audit2", "", "");'
        code += 'echo json_encode(array("rejected"=>$result===false,"error"=>$db->errno));'
    elif changes.get('prepare'):
        code += '$result=@$db->prepare("SELECT 1");'
        code += 'echo json_encode(array("rejected"=>$result===false,"error"=>$db->errno));'
    else:
        code += '$result=@$db->query("SELECT value FROM t");'
        # 文本行按 fetch 时机解码；仅检查 query 对象会漏掉真正的数据边界路径。
        code += '$row=is_object($result)?@$result->fetch_row():null;'
        condition = '$result===false || $row!==null || $result->num_rows!==0' if changes.get('empty') else '$result===false || $row!==array("ok")'
        code += 'echo json_encode(array("rejected"=>' + condition + ',"row"=>$row,"error"=>$db->errno));'
    process = subprocess.run(['php', '-n', '-d', 'display_errors=0', '-r', code],
        capture_output=True, text=True, timeout=12)
    thread.join(timeout=8)
    try:
        response = json.loads(process.stdout)
    except ValueError:
        response = {}
    expected_rejection = changes.get('expected_rejection', name not in ('正常协议控制', '正常空结果控制'))
    passed = process.returncode == 0 and response.get('rejected') == expected_rejection
    results.append({'case': name, 'passed': passed, 'exit_code': process.returncode,
            'response': response, 'stderr': process.stderr})
    print(('通过：' if passed else '失败：') + name, flush=True)
if not all(result['passed'] for result in results):
    print(json.dumps(results, ensure_ascii=False, indent=2))
    raise SystemExit(1)
print('MySQL 正常协议与截断包回归全部通过。', flush=True)
