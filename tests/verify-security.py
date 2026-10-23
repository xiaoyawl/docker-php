#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : verify-security.py
# @Desc     : 在隔离容器内验证安全修复、CGI 与默认 CA 信任路径。
# @Contact  : admin@dstw.com
import pathlib
import subprocess
import sys
import uuid

image, platform = sys.argv[1:3]
root = pathlib.Path(__file__).resolve().parent
name = 'php-security-' + uuid.uuid4().hex[:10]


def run(args, allowed=(0,), **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, timeout=60, **kwargs)
    if result.returncode not in allowed:
        raise RuntimeError('隔离安全回归失败：' + result.stdout + result.stderr)
    return result.stdout


base = ['docker', 'run', '--rm', '--pull=never', '--platform', platform, '--network', 'none',
    '--memory', '256m', '--cpus', '2', '--pids-limit', '64', '--ulimit', 'core=0',
    '-v', str(root) + ':/tests:ro']
print(run(base + [image, 'php', '/tests/security-smoke.php']).strip(), flush=True)
print(run(base + [image, 'python3', '/tests/mysql-protocol.py']).strip(), flush=True)
print(run(base + [image, 'python3', '/tests/http-security.py']).strip(), flush=True)
soap = run(base + [image, 'php', '/tests/security-soap.php'], allowed=(0, 255))
if 'missing value' not in soap:
    raise RuntimeError('SOAP 缺失 value 必须返回受控 Fault')
print('SOAP 畸形 map 受控失败验证通过', flush=True)
cgi = run(base + ['-e', 'REDIRECT_STATUS=200', '-e', 'REQUEST_METHOD=GET',
        '-e', 'SCRIPT_FILENAME=/tests/request.php', '-e', 'SCRIPT_NAME=/request.php',
        image, 'php-cgi'])
if 'Content-type:' not in cgi and 'Content-Type:' not in cgi:
    raise RuntimeError('CGI 未返回响应头')
print('CGI 独立请求验证通过', flush=True)

# 自建测试 CA 仅添加在一次性容器内；不挂载或改动宿主信任库。
tls = r'''
set -Eeuo pipefail
mkdir -p /tmp/php-ca /usr/local/share/ca-certificates
openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/php-ca/ca.key -out /tmp/php-ca/ca.crt -days 1 -subj /CN=PHP-TEST-CA >/dev/null 2>&1
openssl req -new -newkey rsa:2048 -nodes -keyout /tmp/php-ca/server.key -out /tmp/php-ca/server.csr -subj /CN=localhost >/dev/null 2>&1
printf 'subjectAltName=DNS:localhost
extendedKeyUsage=serverAuth
' > /tmp/php-ca/extensions
openssl x509 -req -in /tmp/php-ca/server.csr -CA /tmp/php-ca/ca.crt -CAkey /tmp/php-ca/ca.key -CAcreateserial -out /tmp/php-ca/server.crt -days 1 -extfile /tmp/php-ca/extensions >/dev/null 2>&1
openssl s_server -quiet -accept 19443 -cert /tmp/php-ca/server.crt -key /tmp/php-ca/server.key -www >/tmp/php-ca/server.log 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT
sleep 1
# 更新前不信任测试 CA；更新后 cURL 与 PHP stream 都使用默认路径成功。
php -r '$c=curl_init("https://localhost:19443/");curl_setopt($c,CURLOPT_RETURNTRANSFER,true);if(curl_exec($c)!==false || curl_errno($c)!==60)exit(1);'
cp /tmp/php-ca/ca.crt /usr/local/share/ca-certificates/php-test.crt
update-ca-certificates >/dev/null
php -r '$f="/etc/ssl/certs/ca-certificates.crt";if(ini_get("openssl.cafile")!==$f || ini_get("curl.cainfo")!==$f || !is_readable($f))exit(1);$c=curl_init("https://localhost:19443/");curl_setopt($c,CURLOPT_RETURNTRANSFER,true);if(curl_exec($c)===false)exit(2);if(file_get_contents("https://localhost:19443/")===false)exit(3);$ctx=stream_context_create(array("ssl"=>array("peer_name"=>"wrong.test")));if(@file_get_contents("https://localhost:19443/",false,$ctx)!==false)exit(4);echo "默认 CA 信任及错误主机名拒绝验证通过\n";'
# SAN 与 CN 不一致时禁止回退 CN；含 wildcard 的边界证书必须受控拒绝。
openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/php-ca/mismatch.key -out /tmp/php-ca/mismatch.crt -days 1 -subj /CN=victim.test -addext subjectAltName=DNS:other.test >/dev/null 2>&1
kill "$server"; wait "$server" 2>/dev/null || true
openssl s_server -quiet -accept 19443 -cert /tmp/php-ca/mismatch.crt -key /tmp/php-ca/mismatch.key -www >/tmp/php-ca/server.log 2>&1 &
server=$!
sleep 1
php -r '$ctx=stream_context_create(array("ssl"=>array("cafile"=>"/tmp/php-ca/mismatch.crt","peer_name"=>"victim.test")));if(@file_get_contents("https://127.0.0.1:19443/",false,$ctx)!==false)exit(1);echo "SAN 不匹配禁止回退 CN 验证通过\n";'

# 合法 wildcard 为阳性控制；多级主机名与前后缀过长的 wildcard 必须拒绝。
for san in '*.example.test' 'prefix*suffix.example.test'; do
    kill "$server"; wait "$server" 2>/dev/null || true
    openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/php-ca/wildcard.key -out /tmp/php-ca/wildcard.crt -days 1 -subj /CN=unused.test -addext "subjectAltName=DNS:$san" >/dev/null 2>&1
    openssl s_server -quiet -accept 19443 -cert /tmp/php-ca/wildcard.crt -key /tmp/php-ca/wildcard.key -www >/tmp/php-ca/server.log 2>&1 &
    server=$!
    sleep 1
    if [[ $san == '*.example.test' ]]; then
        php -r '$c=stream_context_create(array("ssl"=>array("cafile"=>"/tmp/php-ca/wildcard.crt","peer_name"=>"a.example.test")));if(@file_get_contents("https://127.0.0.1:19443/",false,$c)===false)exit(1);$c=stream_context_create(array("ssl"=>array("cafile"=>"/tmp/php-ca/wildcard.crt","peer_name"=>"a.b.example.test")));if(@file_get_contents("https://127.0.0.1:19443/",false,$c)!==false)exit(2);'
    else
        php -r '$c=stream_context_create(array("ssl"=>array("cafile"=>"/tmp/php-ca/wildcard.crt","peer_name"=>"x.test")));if(@file_get_contents("https://127.0.0.1:19443/",false,$c)!==false)exit(1);'
    fi
done
echo 'TLS wildcard 阳性控制、层级与前后缀边界验证通过'
'''
print(run(base + [image, 'bash', '-c', tls]).strip(), flush=True)
print('安全修复、原生模块、CGI 与 CA 隔离回归完成：' + platform, flush=True)
