#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : verify.py
# @Desc     : 在构建节点验证镜像功能、开关、FPM 请求与内存耗尽恢复。
# @Contact  : admin@dstw.com
import json
import os
import pathlib
import subprocess
import sys
import time
import uuid

image = sys.argv[1]
platform = sys.argv[2] if len(sys.argv) > 2 else 'linux/amd64'
root = pathlib.Path(__file__).resolve().parent
project = root.parent
name = 'php-check-' + uuid.uuid4().hex[:10]
# 期望值全部来自分支清单 config/extensions.json 与 sources.lock.json，测试脚本不写死版本。
manifest = json.loads((project / 'config/extensions.json').read_text())
php_version = manifest['php']
variant = os.environ.get('VARIANT_SUFFIX', '-')
# 目标架构由平台参数决定，manifest 据此筛选该架构提供的官方 Loader。
arch = platform.split('/')[-1]
os.environ['TARGETARCH'] = arch
loaders = [item for item in manifest['loaders'] if item.get('arch', arch) == arch]
expected = json.loads(subprocess.run([sys.executable, str(project / 'scripts/manifest.py'), 'expected-versions', variant],
    check=True, text=True, capture_output=True).stdout)
switches = sorted({item['switch'] for item in manifest['extensions']})
loader_switches = [item['switch'] for item in loaders]


def run(args, **kwargs):
    kwargs.setdefault('timeout', 60)
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs).stdout


def require(ok, message):
    if not ok:
        raise RuntimeError('验证失败：' + message)


base = ['docker','run','--rm','--pull=never','--platform',platform,'--network','none','--memory','256m',
    '-v',str(root)+':/tests:ro']
def enable(*names):
    result = []
    for item in names:
        result += ['-e', item + '=enable']
    return result


smoke_env = ['-e', 'PHP_EXPECTED_VERSION=' + php_version, '-e', 'PHP_NATIVE_MODULES=' + json.dumps(manifest['native_modules'])]
print(run(base + smoke_env + [image, 'php', '/tests/smoke.php']).strip(), flush=True)
print(run(base + [image, 'php', '/tests/external-dependencies.php']).strip(), flush=True)
print(run(base + [image, 'php', '/tests/timezonedb.php']).strip(), flush=True)
print(run(base + [image, 'php', '/tests/libgd-rotate.php']).strip(), flush=True)
gd_link = run(base + ['--entrypoint', 'sh', image, '-c', 'ldd /usr/local/php/bin/php | grep libgd'])
require('libgd.so.3 => /opt/libgd/lib/libgd.so.3' in gd_link and '/usr/lib/libgd.so' not in gd_link, 'GD 链接补丁版 /opt/libgd')
system_gd = subprocess.run(base + ['--entrypoint', 'apk', image, 'info', '-e', 'libgd'], capture_output=True, text=True)
require(system_gd.returncode != 0, '运行镜像未安装系统 libgd')
run(base + [image, 'php-fpm', '-t'])

# 默认状态：第三方扩展与 Loader 全部关闭，OPcache 默认开启。
defaults = run(base + [image, 'php', '-r', 'echo json_encode(get_loaded_extensions(false)), "\\n", json_encode(get_loaded_extensions(true));'])
loaded = [name.lower() for line in defaults.splitlines() for name in json.loads(line)]
for module in expected:
    require(module.lower() not in loaded, '默认关闭 ' + module)
require('zend opcache' in loaded, 'OPcache 默认开启')
opcache_off = run(base + ['-e', 'OPCACHE=disable', image, 'php', '-r', 'echo (int) ini_get("opcache.enable_cli"), function_exists("opcache_get_status") && opcache_get_status() !== false ? 1 : 0;'])
require(opcache_off.strip() in ('00', ''), 'OPCACHE=disable 关闭缓存')

# 打开除 Xdebug 外的全部开关，逐项核对版本；Xdebug 与 ionCube 互斥，单独核对。
probe = 'echo json_encode(array_map(function ($m) { return phpversion($m); }, json_decode(getenv("MODULES"), true)));'
modules = [m for m in expected if m != 'xdebug']
others = [s for s in switches + loader_switches if s != 'XDEBUG']
versions = json.loads(run(base + enable(*others) + ['-e', 'MODULES=' + json.dumps(modules), image, 'php', '-r', probe]))
for module, version in zip(modules, versions):
    require(version == expected[module], '{} 版本应为 {}，实际 {}'.format(module, expected[module], version))
if 'xdebug' in expected:
    actual = run(base + enable('XDEBUG') + [image, 'php', '-r', 'echo phpversion("xdebug");']).strip()
    require(actual == expected['xdebug'], 'Xdebug 版本应为 {}，实际 {}'.format(expected['xdebug'], actual))
print('扩展与 Loader 版本核对通过：' + json.dumps(expected, ensure_ascii=False), flush=True)
if loaders:
    # 组合用例只包含当前架构实际提供的 Loader（例如 5.6 arm64 只有 ionCube）。
    modules_expr = ' && '.join('extension_loaded("{}")'.format(item['module']) for item in loaders)
    combo = run(base + enable(*loader_switches) + [image, 'php', '-r',
        'echo ' + modules_expr + ' && extension_loaded("Zend OPcache") ? "ok" : "fail";'])
    names = '、'.join(item['module'] for item in loaders)
    require(combo.strip() == 'ok', names + ' 与 OPcache 组合加载')
    message = names + ' 与 OPcache 组合加载通过'
    if 'IONCUBE' in loader_switches:
        conflict = subprocess.run(base + enable('IONCUBE', 'XDEBUG') + [image, 'php', '-v'], capture_output=True, text=True)
        require(conflict.returncode != 0 and '不可同时启用' in conflict.stderr, '拒绝 ionCube/Xdebug 冲突')
        message += '；拒绝 ionCube/Xdebug 同时启用'
    print(message, flush=True)

print(run(base + enable('MONGODB', 'ZSTD', 'EVENT') + [image, 'php', '/tests/additional-extensions.php']).strip(), flush=True)
print(run(base + enable(*others) + [image, 'php', '-d', 'apc.enable_cli=1', '/tests/optional-extensions.php']).strip(), flush=True)
if 'xdebug' in expected:
    # Xdebug 3 需显式开启 coverage、trace 模式；Xdebug 2 忽略该配置项。
    print(run(base + enable('XDEBUG') + [image, 'php', '-d', 'xdebug.mode=coverage,trace', '/tests/xdebug-smoke.php']).strip(), flush=True)
print(run(base + enable('REDIS') + [image, 'php', '/tests/redis-api.php']).strip()[:200], flush=True)

# Swoole：新旧接口二选一，验证定时器与事件循环。
swoole = run(base + enable('SWOOLE') + [image, 'php', '-r',
    '$after = function_exists("swoole_timer_after") ? "swoole_timer_after" : array("Swoole\\\\Timer", "after");'
    '$wait = function_exists("swoole_event_wait") ? "swoole_event_wait" : array("Swoole\\\\Event", "wait");'
    'call_user_func($after, 1, function () { echo "Swoole 定时器验证通过"; }); call_user_func($wait);'])
require('Swoole 定时器验证通过' in swoole, 'Swoole 事件循环')

# git 与 Composer：Composer 包装脚本只为自身进程解除禁用函数，业务 PHP 仍保持禁用。
tools = run(base + ['--tmpfs', '/work', '-e', 'COMPOSER_ALLOW_SUPERUSER=1', image, 'sh', '-c',
    'git --version && composer --version --no-ansi | head -1 && cd /work '
    '&& printf "%s" \'{"name":"lookback/check","scripts":{"probe":"echo composer-script-ok"}}\' > composer.json '
    '&& COMPOSER_HOME=/work/.composer composer run-script probe --no-ansi 2>&1 | tail -1 '
    '&& php -r \'echo ini_get("disable_functions") === "" ? "disable-empty" : "disable-kept";\''])
require('composer-script-ok' in tools and 'disable-kept' in tools, 'Composer 可执行脚本且业务 PHP 禁用函数保持')
print('git 与 Composer 验证通过：' + ' / '.join(line for line in tools.splitlines()[:2]), flush=True)


def request(query='', body='', content_type='application/x-www-form-urlencoded'):
    return run(['docker','exec','-i','-e','SCRIPT_FILENAME=/tests/request.php','-e','SCRIPT_NAME=/request.php',
            '-e','REQUEST_METHOD=' + ('POST' if body else 'GET'),'-e','QUERY_STRING='+query,
            '-e','CONTENT_TYPE='+content_type,'-e','CONTENT_LENGTH='+str(len(body.encode())),
            name,'cgi-fcgi','-bind','-connect','127.0.0.1:9000'], input=body)


def payload(response):
    return json.loads(response.split('\r\n\r\n')[-1] if '\r\n\r\n' in response else response.split('\n\n')[-1])


try:
    run(base[:2] + ['-d','--name',name] + base[3:] + ['-e','PHP_FPM_CONF=/tests/fpm.conf',image])
    first = None
    for attempt in range(30):
        try:
            first = payload(request())
            break
        except (subprocess.CalledProcessError, ValueError):
            time.sleep(0.3)
    require(first is not None, 'FPM 启动')
    require(first['memory_limit'] == '64M', 'cgroup 内存识别')
    require(first['timezone'] == 'Asia/Shanghai', '时区默认值')
    status = run(['docker','exec','-e','SCRIPT_FILENAME=/php-fpm_status',
            '-e','SCRIPT_NAME=/php-fpm_status','-e','REQUEST_METHOD=GET',
            name,'cgi-fcgi','-bind','-connect','127.0.0.1:9000'])
    require('pool:' in status and 'active processes:' in status, 'FPM 状态路径')
    run(['docker','exec',name,'openssl','req','-x509','-newkey','rsa:2048','-nodes',
            '-keyout','/tmp/php-tls.key','-out','/tmp/php-tls.crt','-days','1',
            '-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost'])
    run(['docker','exec','-d',name,'openssl','s_server','-quiet','-accept','9443',
            '-cert','/tmp/php-tls.crt','-key','/tmp/php-tls.key','-www'])
    time.sleep(0.3)
    tls = run(['docker','exec',name,'php','-r',
            '$c=curl_init("https://localhost:9443/"); curl_setopt($c,CURLOPT_RETURNTRANSFER,true); '
            'curl_setopt($c,CURLOPT_CAINFO,"/tmp/php-tls.crt"); '
            'if(curl_exec($c)===false || curl_getinfo($c,CURLINFO_HTTP_CODE)!==200){exit(1);} '
            '$d=curl_init("https://localhost:9443/");curl_setopt($d,CURLOPT_RETURNTRANSFER,true); '
            'if(curl_exec($d)!==false || curl_errno($d)!==60){exit(1);} '
            '$ctx=stream_context_create(array("ssl"=>array("cafile"=>"/tmp/php-tls.crt","verify_peer"=>true,"verify_peer_name"=>true))); '
            'if(file_get_contents("https://localhost:9443/",false,$ctx)===false){exit(1);} '
            '$fp=fopen("php://temp","w+");$e=curl_init("https://localhost:9443/"); '
            'curl_setopt($e,CURLOPT_CAINFO,"/tmp/php-tls.crt");curl_setopt($e,CURLOPT_FILE,$fp); '
            'if(!curl_exec($e)){exit(1);}fflush($fp);rewind($fp);if(strlen(stream_get_contents($fp))===0){exit(1);} '
            'echo "本地 HTTPS 证书校验、PHP TLS 流与 stdio 转换验证通过";'])
    print(tls, flush=True)
    second = payload(request(body='item%5Bx%5D=hello'))
    require(second['pid'] == first['pid'] and second['post']['item']['x'] == 'hello', '同 worker POST 解析')
    body = '--testboundary\r\nContent-Disposition: form-data; name="PHP_SESSION_UPLOAD_PROGRESS"\r\n\r\ntest\r\n--testboundary\r\nContent-Disposition: form-data; name="file"; filename="a.txt"\r\nContent-Type: text/plain\r\n\r\nhello\r\n--testboundary--\r\n'
    uploaded = payload(request(body=body, content_type='multipart/form-data; boundary=testboundary'))
    require(uploaded['files'] == 1 and uploaded['pid'] == first['pid'], '同 worker multipart 上传')
    request('fatal=1')
    recovered = payload(request())
    require(recovered['pid'] == first['pid'], '普通 fatal 后同 worker 恢复')
    require(recovered['post'] == [] and recovered['files'] == 0, '同 worker 请求数据清理')
    try:
        request('oom=1')
    except subprocess.CalledProcessError:
        pass
    after = None
    for attempt in range(30):
        try:
            after = payload(request())
            break
        except (subprocess.CalledProcessError, ValueError):
            time.sleep(0.2)
    require(after is not None, '内存耗尽后 FPM 恢复服务')
    # 5.6 的 EOL 缓解补丁在内存耗尽路径让 worker 退出并由 master 补充；官方修复则安全清理后由同一 worker 继续服务。
    if manifest.get('fpm', {}).get('oom_worker_exits', True):
        require(after['pid'] != first['pid'], '内存耗尽退出后创建新 worker')
    else:
        require(after['version'] == php_version and after['post'] == [] and after['files'] == 0
            and after['memory_limit'] == first['memory_limit'], '内存耗尽后同一 worker 请求状态完整复原')
    run(['docker','exec','-e','REDIS=enable',name,'/entrypoint.sh','php','-m'])
    toggled = run(['docker','exec','-e','REDIS=disable',name,'/entrypoint.sh','php','-m'])
    require('redis' not in toggled.splitlines(), '同一文件系统扩展开关清理')
    run(['docker','restart',name])
    restarted = None
    for attempt in range(50):
        try:
            restarted = payload(request())
            break
        except (subprocess.CalledProcessError, ValueError):
            time.sleep(0.3)
    require(restarted is not None and restarted['version'] == php_version, '容器重启就绪')
    run(['docker','stop','--time','20',name])
    result = json.loads(run(['docker','inspect',name]))[0]
    require(result['State']['ExitCode'] == 0 and not result['State']['OOMKilled'], 'SIGTERM 优雅退出')
    print('FPM 同 worker 请求、multipart、fatal、OOM 补进程、重启及退出验证通过', flush=True)
finally:
    logs = subprocess.run(['docker','logs',name], text=True, capture_output=True)
    print(logs.stdout + logs.stderr, flush=True)
    subprocess.run(['docker','rm','-f',name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
# 官方 Loader 在 FPM worker 中加载：入口脚本设置的 LD_PRELOAD 须被 Supervisor 与 FPM 继承。
if loader_switches:
    loader_name = 'php-loader-' + uuid.uuid4().hex[:10]
    try:
        run(base[:2] + ['-d', '--name', loader_name] + base[3:] + ['-e', 'PHP_FPM_CONF=/tests/fpm.conf'] + enable(*loader_switches) + [image])
        output = ''
        for attempt in range(40):
            try:
                output = run(['docker', 'exec', '-e', 'SCRIPT_FILENAME=/tests/loaders.php', '-e', 'SCRIPT_NAME=/loaders.php',
                    '-e', 'REQUEST_METHOD=GET', loader_name, 'cgi-fcgi', '-bind', '-connect', '127.0.0.1:9000'])
                if 'LOADERS ' in output:
                    break
            except subprocess.CalledProcessError:
                pass
            time.sleep(0.3)
        require('LOADERS ' in output, 'FPM 中 Loader 探测请求')
        loaded = json.loads(output.split('LOADERS ', 1)[1].strip().splitlines()[0])
        for item in loaders:
            require(loaded.get(item['module']) == expected[item['module']], 'FPM 中加载 ' + item['module'])
        print('FPM worker 中官方 Loader 加载通过：' + json.dumps(loaded, ensure_ascii=False), flush=True)
    finally:
        subprocess.run(['docker', 'rm', '-f', loader_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print('验证完成：'+platform, flush=True)
