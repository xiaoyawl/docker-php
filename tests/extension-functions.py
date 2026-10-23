#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : extension-functions.py
# @Desc     : 在断网容器内部验证 Swoole 旧类名 TCP 收发和 Xdebug 覆盖率、跟踪。
# @Contact  : admin@dstw.com
from pathlib import Path
import socket
import subprocess
import time

php = '/usr/local/php/bin/php'
extension_dir = subprocess.check_output([php, '-r', 'echo ini_get("extension_dir");'], text=True).strip()
tests = Path(__file__).resolve().parent
with socket.socket() as reservation:
    reservation.bind(('127.0.0.1', 0))
    port = reservation.getsockname()[1]
# Swoole 5/6 已移除 swoole_server 等旧类名（use_shortname 也不恢复），按存在性选择；旧版本继续验证现网旧类名。
server_code = '''$S=class_exists("swoole_server")?"swoole_server":"Swoole\\\\Server";
$server=new $S("127.0.0.1",%d,SWOOLE_BASE,SWOOLE_SOCK_TCP);
$server->set(array("worker_num"=>1,"log_file"=>"/tmp/swoole-compat.log"));
$server->on("receive",function($server,$fd,$reactor,$data){$server->send($fd,"回声:".$data);});
$server->start();''' % port
command = [php, '-n', '-d', 'extension=' + extension_dir + '/swoole.so', '-d', 'swoole.use_namespace=Off']
server = subprocess.Popen([*command, '-r', server_code], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
try:
    for attempt in range(100):
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.3):
                break
        except OSError:
            if server.poll() is not None:
                raise RuntimeError('Swoole 服务退出：' + server.stdout.read().decode(errors='replace'))
            time.sleep(0.1)
    else:
        raise RuntimeError('Swoole TCP 服务启动超时')
    client_code = '''$C=class_exists("swoole_client")?"swoole_client":"Swoole\\\\Client";
$client=new $C(SWOOLE_SOCK_TCP);
if(!$client->connect("127.0.0.1",%d,2)){exit(1);}
$client->send("中文兼容");$data=$client->recv();$client->close();
if($data!=="回声:中文兼容"){exit(1);} echo "Swoole ",swoole_version(),"（",$C,"）TCP 服务与客户端收发验证通过\\n";''' % port
    result = subprocess.run([*command, '-r', client_code], capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise RuntimeError('Swoole 收发验证失败：' + result.stdout + result.stderr)
    print(result.stdout.strip(), flush=True)
finally:
    server.terminate()
    try:
        server.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        server.kill()
        server.communicate()
result = subprocess.run([php, '-n', '-d', 'zend_extension=' + extension_dir + '/xdebug.so',
        '-d', 'xdebug.remote_enable=0', '-d', 'xdebug.mode=coverage,trace', str(tests / 'xdebug-smoke.php')],
    capture_output=True, text=True, timeout=20)
if result.returncode:
    raise RuntimeError('Xdebug 功能验证失败：' + result.stdout + result.stderr)
print(result.stdout.strip(), flush=True)
