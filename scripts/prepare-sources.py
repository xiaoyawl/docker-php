#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : prepare-sources.py
# @Desc     : 校验固定源码与补丁并严格应用补丁序列。
# @Contact  : admin@dstw.com
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import tarfile
import urllib.request

root = Path(__file__).resolve().parent.parent
lock = json.loads((root / 'sources.lock.json').read_text())
php_version = json.loads((root / 'config/extensions.json').read_text())['php']
cache = root / '.cache/sources'
# 只处理当前目标架构需要的源码（如各架构的官方 Loader 包）；未声明 arch 的源码适用于所有架构。
arch = os.environ.get('TARGETARCH') or 'amd64'
lock['sources'] = [s for s in lock['sources'] if s.get('arch', arch) == arch]
lock['binary_loaders'] = [l for l in lock.get('binary_loaders', []) if l.get('arch', arch) == arch]
cache.mkdir(parents=True, exist_ok=True)


def verify(path, expected):
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit('校验失败：' + str(path))


for source in lock['sources']:
    path = cache / source['file']
    if not path.exists():
        print('下载源码：' + source['file'], flush=True)
        with urllib.request.urlopen(source['url'], timeout=120) as response:
            path.write_bytes(response.read())
    verify(path, source['sha256'])

patch_root = root / 'patches'
series = (patch_root / 'series').read_text().splitlines()
if series != [p['file'] for p in lock['patches']]:
    raise SystemExit('补丁序列与锁文件不一致')
for item in lock['patches']:
    verify(patch_root / item['file'], item['sha256'])

source_root = root / '.cache/work'
if source_root.exists():
    raise SystemExit('源码工作目录已存在，请使用新的构建目录，避免重复应用补丁')
source_root.mkdir()
for source in lock['sources']:
    if source.get('extract', True) is False:
        # 单文件工具（如 composer.phar）校验后原样放入工作目录。
        (source_root / source['file']).write_bytes((cache / source['file']).read_bytes())
        continue
    # 根目录直接平铺文件的压缩包（如 SourceGuardian Loader）解压到指定子目录。
    target = source_root / source.get('extract_dir', '')
    target.mkdir(exist_ok=True)
    with tarfile.open(cache / source['file']) as archive:
        archive.extractall(target, filter='data')
php_root = source_root / ('php-' + php_version)
for item in lock['patches']:
    path = patch_root / item['file']
    print('应用补丁：' + item['file'], flush=True)
    files = sorted(set(re.findall(r'^(?:--- a/|\+\+\+ b/)(.+)$', path.read_bytes().decode('latin1'), re.M)))
    before = {name: hashlib.sha256((php_root / name).read_bytes()).hexdigest()
        if (php_root / name).exists() else None for name in files}
    subprocess.run(['git', 'apply', '--check', '--binary', str(path)], cwd=php_root, check=True)
    subprocess.run(['git', 'apply', '--binary', '--whitespace=nowarn', str(path)], cwd=php_root, check=True)
    after = {name: hashlib.sha256((php_root / name).read_bytes()).hexdigest()
        if (php_root / name).exists() else None for name in files}
    if before == after:
        raise SystemExit('补丁没有实际改变文件：' + item['file'])
print('源码与补丁校验完成', flush=True)
