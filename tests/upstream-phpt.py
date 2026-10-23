#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-23 03:30:00
# @Author   : LookBack
# @Site     : Asia.DSTW.com
# @Project  : docker-php
# @File     : upstream-phpt.py
# @Software : Python
# @Desc     : 在构建阶段镜像内以官方 run-tests.php 运行上游 PHPT：补丁附带用例 + 版本额外清单，输出统计与失败明细。
# @License  : (C) Copyright 2013-2026, DSTW Corporation Limited.
# @Contact  : admin@dstw.com
import glob
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

results = Path(sys.argv[1])
build = Path('/build')
php_version = json.loads((build / 'config/extensions.json').read_text())['php']
source = build / '.cache/work' / ('php-' + php_version)
# 源码复制到独立的 /work（不放在 /tmp 下），避免与 open_basedir=/tmp 等用例的测试目录重叠。
work = Path('/work/phpt-src')
php = '/usr/local/php/bin/php'

# 以非 root 运行（容器 --user 指定），源码复制到可写的临时目录后执行。
print('复制 PHP ' + php_version + ' 源码到临时目录', flush=True)
shutil.copytree(source, work, symlinks=True)

# 用例一：补丁序列中新增或修改的 .phpt（安全回补自带的回归测试）。
tests = set()
for name in (build / 'patches/series').read_text().split():
    data = (build / 'patches' / name).read_bytes().decode('latin1')
    tests.update(re.findall(r'^\+\+\+ b/(.*\.phpt)$', data, re.M))
patch_tests = len(tests)
# 用例二：版本额外清单（相对源码根目录的文件、目录或通配符，# 为注释）。
extra_file = Path('/tests/upstream-phpt-extra.txt')
if extra_file.exists():
    for line in extra_file.read_text().splitlines():
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        for match in glob.glob(str(work / line), recursive=True):
            path = Path(match)
            tests.update(str(p.relative_to(work)) for p in ([path] if path.is_file() else path.rglob('*.phpt')))
existing = sorted(t for t in tests if (work / t).is_file())
missing = sorted(t for t in tests if not (work / t).is_file())
print('补丁附带用例 {} 个，总计 {} 个，源码中不存在 {} 个'.format(patch_tests, len(existing), len(missing)), flush=True)

environment = dict(os.environ, TEST_PHP_EXECUTABLE=php, TEST_PHP_CGI_EXECUTABLE='/usr/local/php/bin/php-cgi',
    NO_INTERACTION='1', REPORT_EXIT_STATUS='0', SKIP_SLOW_TESTS='1', SKIP_ONLINE_TESTS='1', SKIP_IO_CAPTURE_TESTS='1')
summary = Path('/tmp/phpt-summary.txt')
completed = subprocess.run([php, 'run-tests.php', '-q', '-s', str(summary), *existing], cwd=work, env=environment,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors='replace', timeout=int(os.environ.get('PHPT_TIMEOUT', '7200')))
(results / 'run-tests.log').write_text(completed.stdout)
text = summary.read_text(errors='replace') if summary.exists() else completed.stdout

counts = {}
for key, label in [('skipped', 'Tests skipped'), ('warned', 'Tests warned'), ('failed', 'Tests failed'),
        ('xfailed', 'Expected fail'), ('passed', 'Tests passed'), ('total', 'Number of tests')]:
    match = re.search(r'^' + label + r'\s*:\s*(\d+)', text, re.M)
    counts[key] = int(match.group(1)) if match else None
failed = []
block = re.search(r'FAILED TEST SUMMARY\n-+\n(.*?)\n=+', text, re.S)
if block:
    for line in block.group(1).splitlines():
        found = re.search(r'\[([^\]]+\.phpt)\]', line)
        if found:
            failed.append({'test': found.group(1), 'title': line.split('[')[0].strip()})
            for suffix in ('.diff', '.out'):
                artifact = work / found.group(1).replace('.phpt', suffix)
                if artifact.exists():
                    target = results / 'failed' / (found.group(1).replace('/', '__').replace('.phpt', suffix))
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(artifact, target)
report = {'php': php_version, 'runner': 'run-tests.php（官方）', 'user': os.getuid(), 'patch_tests': patch_tests,
    'selected': len(existing), 'missing_in_source': missing, 'counts': counts, 'failed': failed}
(results / 'upstream-phpt.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
shutil.copyfile(summary, results / 'summary.txt') if summary.exists() else None
print('上游 PHPT：' + json.dumps(counts, ensure_ascii=False), flush=True)
print('失败 {} 项，明细见 upstream-phpt.json 与 failed/；失败项需逐项分类，不能直接视为通过。'.format(len(failed)), flush=True)
