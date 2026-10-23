#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : upstream-regressions.py
# @Desc     : 在一次性构建阶段容器内执行所选补丁的上游 PHPT 回归并记录跳过原因。
# @Contact  : admin@dstw.com
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import uuid

php_version = json.loads(Path('/build/config/extensions.json').read_text())['php']
root = Path('/build/.cache/work/php-' + php_version)
patch_root = Path('/build/patches')
php = '/usr/local/php/bin/php'
cgi = '/usr/local/php/bin/php-cgi'
report = Path(sys.argv[1])
paths = set()
for name in (patch_root / 'series').read_text().splitlines():
    data = (patch_root / name).read_bytes().decode('latin1')
    paths.update(re.findall(r'^\+\+\+ b/(.*\.phpt)$', data, re.M))

environment = os.environ.copy()
environment.update(TEST_PHP_EXECUTABLE=php, TEST_PHP_CGI_EXECUTABLE=cgi, SKIP_SLOW_TESTS='1',
    ASAN_OPTIONS='detect_leaks=0:abort_on_error=1', UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')


def execute(command, data=b'', env=None):
    proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, env=env or environment, start_new_session=True, cwd=temporary.parent)
    try:
        output = proc.communicate(data, timeout=25)[0]
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        return -999, '回归超时'
    return proc.returncode, output.decode('latin1')


def expected_pattern(text):
    replacements = {'%s': '[^\r\n]+', '%S': '[^\r\n]*', '%a': '.+', '%A': '.*',
        '%w': '\\s*', '%i': '[+-]?\\d+', '%d': '\\d+', '%x': '[0-9a-fA-F]+',
        '%f': '[+-]?(?:\\d*\\.)?\\d+(?:[Ee][+-]?\\d+)?', '%c': '.', '%e': '/', '%%': '%'}
    text = text.replace('%unicode|string%', 'string').replace('%string|unicode%', 'string').replace('%u|b%', '').replace('%b|u%', '')
    parts = text.split('%r')
    for i in range(0, len(parts), 2):
        parts[i] = re.escape(parts[i])
        for old, new in replacements.items():
            parts[i] = parts[i].replace(re.escape(old), new)
    return ''.join(parts)


results = []
if len(sys.argv) > 2:
    paths = {name for name in paths if any(part in name for part in sys.argv[2:])}

for name in sorted(paths):
    path = root / name
    if not path.exists():
        results.append({'test': name, 'status': 'SKIP', 'reason': '后续补丁已删除或改名'})
        continue
    source = path.read_bytes().decode('latin1').replace('\r\n', '\n')
    pieces = re.split(r'^--([A-Z_]+)--\n', source, flags=re.M)
    sections = dict(zip(pieces[1::2], pieces[2::2]))
    unsupported = set(sections) & {'FILE_EXTERNAL', 'EXPECT_EXTERNAL', 'REDIRECTTEST', 'PHPDBG'}
    if unsupported or 'FILE' not in sections:
        results.append({'test': name, 'status': 'SKIP', 'reason': '需要专用运行器：' + ','.join(sorted(unsupported))})
        continue
    ini = ['-n', '-d', 'display_errors=1', '-d', 'log_errors=0', '-d', 'html_errors=0']
    for line in sections.get('INI', '').splitlines():
        if line and not line.startswith(';'):
            ini += ['-d', line.replace('{PWD}', str(path.parent))]
    temporary = path.with_suffix('.php')
    original = temporary.read_bytes() if temporary.exists() else None
    shim_file = path.parent / ('.lookback-shim-' + uuid.uuid4().hex + '.php')
    shim_file.write_text("<?php if(!defined('PHP_OS_FAMILY')) define('PHP_OS_FAMILY',PHP_OS); ?>")
    if 'PHP_OS_FAMILY' in source:
        ini += ['-d', 'auto_prepend_file=' + str(shim_file)]
    shim = ''
    entry = {'test': name}
    try:
        if 'SKIPIF' in sections:
            temporary.write_bytes((shim + sections['SKIPIF']).encode('latin1'))
            code, output = execute([php, *ini, str(temporary)])
            if output.lstrip().lower().startswith('skip'):
                entry.update(status='SKIP', reason=output.strip())
                results.append(entry)
                continue
        temporary.write_bytes((shim + sections['FILE']).encode('latin1'))
        env = environment.copy()
        for line in sections.get('ENV', '').splitlines():
            if '=' in line:
                key, value = line.split('=', 1)
                env[key] = value
        body = b''
        use_cgi = any(key in sections for key in ('GET', 'POST', 'POST_RAW', 'COOKIE'))
        if use_cgi:
            env.update(REDIRECT_STATUS='200', REQUEST_METHOD='GET', SCRIPT_FILENAME=str(temporary),
                SCRIPT_NAME=temporary.name, GATEWAY_INTERFACE='CGI/1.1', QUERY_STRING=os.fsdecode(sections.get('GET', '').strip().encode('latin1')))
            env['HTTP_COOKIE'] = os.fsdecode(sections.get('COOKIE', '').strip().replace('\n', ' ').encode('latin1'))
            if 'POST_RAW' in sections:
                content = sections['POST_RAW'].encode('latin1')
                if content.lower().startswith(b'content-type:'):
                    header, content = content.split(b'\n', 1)
                    env['CONTENT_TYPE'] = header.split(b':', 1)[1].strip().decode('latin1')
                    content = content.lstrip(b'\n')
                body = content
            elif 'POST' in sections:
                body = sections['POST'].strip().encode('latin1')
                env['CONTENT_TYPE'] = 'application/x-www-form-urlencoded'
            if body:
                env.update(REQUEST_METHOD='POST', CONTENT_LENGTH=str(len(body)))
        code, output = execute([cgi if use_cgi else php, *ini, str(temporary)], body, env)
        output = output.replace('\r\n', '\n')
        if use_cgi and '\n\n' in output:
            output = output.split('\n\n', 1)[1]
        # 测试自己启动的 CLI server 将横幅写入继承的 stderr，与断言内容无关。
        banner = r'^PHP \d+\.\d+\.\d+ Development Server started at [^\n]*\n'
        output, banner_count = re.subn(banner, '', output, flags=re.M)
        if banner_count:
            entry['normalization'] = '移除测试辅助 CLI server 启动横幅'
        output = output.strip()
        expected = sections.get('EXPECT', sections.get('EXPECTF', sections.get('EXPECTREGEX', ''))).strip()
        if 'EXPECT' in sections:
            matched = output == expected
        else:
            pattern = expected_pattern(expected) if 'EXPECTF' in sections else expected
            matched = re.fullmatch(pattern, output, re.S) is not None
        entry['status'] = 'PASS' if matched and code not in (-999, 139, -11, 134, -6) else 'FAIL'
        entry['exit_code'] = code
        if entry['status'] == 'FAIL':
            entry.update(actual=output[:8000], expected=expected[:8000])
    finally:
        if 'CLEAN' in sections:
            temporary.write_bytes((shim + sections['CLEAN']).encode('latin1'))
            execute([php, *ini, str(temporary)])
        if original is None:
            temporary.unlink(missing_ok=True)
        else:
            temporary.write_bytes(original)
        shim_file.unlink(missing_ok=True)
    results.append(entry)
    print(entry['status'] + ' ' + name, flush=True)

report.write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
counts = {status: sum(row['status'] == status for row in results) for status in ('PASS', 'FAIL', 'SKIP')}
print('上游回归统计：' + json.dumps(counts, ensure_ascii=False), flush=True)
raise SystemExit(bool(counts['FAIL']))
