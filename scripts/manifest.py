#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-23 02:40:00
# @Author   : LookBack
# @Site     : Asia.DSTW.com
# @Project  : docker-php
# @File     : manifest.py
# @Software : Python
# @Desc     : 读取分支版本清单（config/extensions.json 等），为构建、入口与测试脚本统一输出版本信息。
# @License  : (C) Copyright 2013-2026, DSTW Corporation Limited.
# @Contact  : admin@dstw.com
import json
import os
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'config/extensions.json').read_text(encoding='utf-8'))
lock = json.loads((root / 'sources.lock.json').read_text(encoding='utf-8'))
# 目标架构：构建时由 buildx 的 TARGETARCH 传入，测试时由平台参数推得；未设置时按 amd64 处理。
arch = os.environ.get('TARGETARCH') or 'amd64'


def for_arch(items):
    # 未声明 arch 的条目适用于所有架构；声明了的只在对应架构生效。
    return [item for item in items if item.get('arch', arch) == arch]


def php_version():
    return manifest['php']


def php_series():
    return '.'.join(php_version().split('.')[:2])


def variant(suffix):
    for item in manifest['variants']:
        if item['suffix'] == suffix:
            return item
    raise SystemExit('未定义的镜像变体：' + repr(suffix))


def lines(path):
    # 读取一行一项的清单文件，忽略空行与 # 注释。
    result = []
    for line in (root / path).read_text(encoding='utf-8').splitlines():
        line = line.split('#', 1)[0].strip()
        if line:
            result.append(line)
    return result


def extension_rows():
    # 输出给 entrypoint.sh 的竖线分隔清单：开关、类型、加载值、额外 ini（以 \x1f 分隔）、预加载库、互斥开关。
    rows = []
    for item in for_arch(manifest['loaders']):
        rows.append(['loader', item['switch'], 'zend' if item['zend'] else 'extension', item['path'],
            '', item.get('preload', ''), item.get('conflicts', '')])
    rows.append(['opcache', 'OPCACHE', 'zend', 'builtin' if manifest['opcache']['builtin'] else 'opcache.so', '', '', ''])
    for item in manifest['extensions']:
        kind = 'zend' if item.get('zend') else 'extension'
        extra = item.get('xdebug_ini', item.get('ini', []))
        rows.append(['extension', item['switch'], kind, item['name'] + '.so', '\x1f'.join(extra), '', ''])
    return '\n'.join('|'.join(row) for row in rows) + '\n'


def build_rows(suffix):
    # 输出给 build-extensions.sh 的竖线分隔清单：扩展名、源码包、额外 CFLAGS、configure 参数（空格分隔）。
    rows = []
    for item in manifest['extensions']:
        package = item['package']
        if package == 'native':
            # PHP 自带、以共享模块编译的扩展（如 FFI），由 build-php.sh 随内核生成。
            continue
        if package == 'variant':
            package = variant(suffix)[item['name']]
        rows.append('|'.join([item['name'], package, item.get('cflags', ''), ' '.join(item.get('configure', []))]))
    return '\n'.join(rows) + '\n'


def expected_versions(suffix):
    # 测试使用：扩展名到期望 phpversion() 的映射。
    result = {}
    for item in manifest['extensions']:
        package = item['package']
        if package == 'native':
            result[item['name']] = php_version()
            continue
        if package == 'variant':
            package = variant(suffix)[item['name']]
        result[item['name']] = package.split('-', 1)[1]
    versions = {item['name']: item['version'] for item in for_arch(lock.get('binary_loaders', []))}
    for item in for_arch(manifest['loaders']):
        result[item['module']] = versions[item['name']]
    return result


commands = {
    'php-version': lambda args: print(php_version()),
    'php-series': lambda args: print(php_series()),
    'variants': lambda args: print('\n'.join(item['suffix'] or '-' for item in manifest['variants'])),
    'opcache-builtin': lambda args: print('1' if manifest['opcache']['builtin'] else '0'),
    'composer-file': lambda args: print(manifest['tools']['composer']),
    'switches': lambda args: print(' '.join(sorted({i['switch'] for i in manifest['extensions']} | {i['switch'] for i in for_arch(manifest['loaders'])}))),
    'loaders': lambda args: print(json.dumps(for_arch(manifest['loaders']), ensure_ascii=False)),
    'configure-args': lambda args: print('\n'.join(lines('config/php-configure.txt'))),
    'build-packages': lambda args: print(' '.join(lines('config/build-packages.txt'))),
    'runtime-packages': lambda args: print(' '.join(lines('config/runtime-packages.txt'))),
    'build-rows': lambda args: sys.stdout.write(build_rows(args[0] if args and args[0] != '-' else '')),
    'extension-rows': lambda args: sys.stdout.write(extension_rows()),
    'expected-versions': lambda args: print(json.dumps(expected_versions(args[0] if args and args[0] != '-' else ''))),
}

if len(sys.argv) < 2 or sys.argv[1] not in commands:
    raise SystemExit('用法：manifest.py ' + '|'.join(sorted(commands)) + ' [变体后缀]')
commands[sys.argv[1]](sys.argv[2:])
