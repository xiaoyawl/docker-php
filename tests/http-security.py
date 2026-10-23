#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : http-security.py
# @Desc     : 仅在断网容器的 loopback 上验证 HTTP 重定向、凭据、头部与长度边界。
# @Contact  : admin@dstw.com
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import subprocess
import threading

requests = []
destination_port = 0
long_path = '/long/' + 'a' * 2500 + '/end'


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        self.do_GET()

    def do_GET(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0'))).decode()
        record = {'path': self.path, 'method': self.command, 'body': body,
            'headers': {key.lower(): value for key, value in self.headers.items()}}
        requests.append(record)
        redirects = {'/cross': 'http://127.0.0.1:%d/echo' % destination_port,
            '/same': '/echo', '/307': '/echo', '/308': '/echo', '/302': '/echo',
            '/long': long_path, '/dir/start': 'a', '/empty': ''}
        if self.path in redirects:
            status = int(self.path[1:]) if self.path in ('/307', '/308', '/302') else 302
            self.send_response(status)
            self.send_header('Location', redirects[self.path])
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.path in ('/folded', '/no-colon', '/nul', '/bad-name'):
            field = {'/folded': b'X-Audit: one\r\n two', '/no-colon': b'InvalidField',
                '/nul': b'X-Audit: one\x00two', '/bad-name': b'Bad Field: x'}[self.path]
            self.wfile.write(b'HTTP/1.0 200 OK\r\n' + field + b'\r\nContent-Length: 2\r\n\r\nok')
            return
        data = json.dumps(record).encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def require(condition, message):
    if not condition:
        raise RuntimeError('HTTP 安全回归失败：' + message)
    print('通过：' + message, flush=True)


def fetch(path, options=None, userinfo=''):
    code = '''$context=json_decode($argv[2],true);
$data=@file_get_contents($argv[1],false,stream_context_create(array("http"=>$context)));
echo json_encode(array("data"=>$data,"headers"=>isset($http_response_header)?$http_response_header:array()));'''
    context = {'timeout': 3, 'max_redirects': 8}
    context.update(options or {})
    result = subprocess.run(['/usr/local/php/bin/php', '-n', '-r', code,
            'http://' + userinfo + '127.0.0.1:%d' % origin.server_port + path,
            json.dumps(context)], capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise RuntimeError('HTTP 测试子进程异常：' + str(result.returncode) + result.stderr)
    return json.loads(result.stdout)


origin = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
destination = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
destination_port = destination.server_port
threads = [threading.Thread(target=server.serve_forever, daemon=True) for server in (origin, destination)]
for thread in threads:
    thread.start()
try:
    credentials = 'Authorization: Bearer audit\r\nCookie: audit=dummy\r\nProxy-Authorization: Basic dummy\r\nX-Audit: keep'
    response = json.loads(fetch('/cross', {'header': credentials})['data'])
    require(not ({'authorization', 'cookie', 'proxy-authorization'} & set(response['headers']))
        and response['headers'].get('x-audit') == 'keep', '跨端口重定向剥离敏感头并保留普通头')
    response = json.loads(fetch('/same', {'header': credentials})['data'])
    require(response['headers'].get('authorization') == 'Bearer audit'
        and response['headers'].get('cookie') == 'audit=dummy', '同源重定向保留认证与 Cookie')
    for status in (307, 308):
        response = json.loads(fetch('/' + str(status), {'method': 'POST', 'content': 'a=中文',
                    'header': 'Content-Type: application/x-www-form-urlencoded'})['data'])
        require(response['method'] == 'POST' and response['body'] == 'a=中文', str(status) + ' 保留 POST 与完整请求体')
    response = json.loads(fetch('/302', {'method': 'POST', 'content': 'a=1',
                'header': 'Content-Type: application/x-www-form-urlencoded'})['data'])
    require(response['method'] == 'GET' and response['body'] == '', '302 重定向按既有规则转为 GET')
    require(json.loads(fetch('/long')['data'])['path'] == long_path, '超过 1024 字节的 Location 不截断')
    # PHP 8 上游对长度为 1 的相对 Location 按根路径拼接（location_len > 1 才相对当前目录），同源且不越界；
    # 5.6 的 /dir/a 来自本地重写的 http wrapper，8.x 保持上游行为。
    require(json.loads(fetch('/dir/start')['data'])['path'] == '/a', '单字符相对 Location 按上游行为同源解析')
    before = len(requests)
    fetch('/empty')
    # PHP 8 上游把空 Location 按相对路径拼接为同源根路径 /，至多再请求一次；不允许跳出同源或多次跳转。
    followed = [item['path'] for item in requests[before:]]
    require(followed in (['/empty'], ['/empty', '/']), '空 Location 受控处理，只在同源内跳转')
    response = json.loads(fetch('/echo', {'header': 'X-Audit: Authorization: embedded'}, 'audit:dummy@')['data'])
    expected = 'Basic ' + base64.b64encode(b'audit:dummy').decode()
    require(response['headers'].get('authorization') == expected, '头部值内的 Authorization 字符串不误判为认证头')
    folded = fetch('/folded')
    require(folded['data'] == 'ok' and 'X-Audit: one two' in folded['headers'], '折叠响应头按字段规范化')
    for path in ('/no-colon', '/bad-name'):
        require(fetch(path)['data'] is False, '拒绝畸形响应头 ' + path)
    # PHP 8 上游不拒绝头字段值中的 NUL，但按长度完整保留、不截断也不拆分为新字段（5.6 本地重写额外拒绝）。
    nul = fetch('/nul')
    require(nul['data'] is False or 'X-Audit: one\x00two' in nul['headers'], '含 NUL 的响应头值被拒绝或完整保留')
finally:
    for server in (origin, destination):
        server.shutdown()
        server.server_close()
    for thread in threads:
        thread.join(timeout=5)
print('HTTP 凭据、重定向与响应头安全回归完成。', flush=True)
