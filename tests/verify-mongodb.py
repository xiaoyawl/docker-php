#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : verify-mongodb.py
# @Desc     : 在独立内部网络使用临时 MongoDB 验证认证与实际读写。
# @Contact  : admin@dstw.com
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
import uuid

image, platform = sys.argv[1:3]
# 可选参数：镜像锁键、PHP 扩展文件、测试脚本；默认验证新版 mongodb 驱动。
lock_key, extension, test_script = (sys.argv[3:6] + ['mongodb', 'mongodb.so', '/tests/mongodb.php'][len(sys.argv[3:6]):])
root = Path(__file__).resolve().parent
mongo_image = json.loads((root / 'images.lock.json').read_text())[lock_key]['image']
suffix = uuid.uuid4().hex[:10]
network, service = 'php-mongo-net-' + suffix, 'php-mongo-' + suffix
environment = os.environ.copy()
password = secrets.token_hex(16)
environment.update(MONGO_INITDB_ROOT_USERNAME='audit', MONGO_INITDB_ROOT_PASSWORD=password,
    PHP_TEST_MONGO_PASSWORD=password)


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, timeout=90, **kwargs)
    if result.returncode:
        raise RuntimeError(('MongoDB 隔离测试命令失败：' + result.stdout + result.stderr).replace(password, '[临时口令已隐藏]'))
    return result.stdout


try:
    run(['docker', 'network', 'create', '--internal', network])
    # MongoDB 服务端固定在构建节点原生架构运行（5.0 起要求较新的 ARM 指令集，QEMU 下可能无法启动）；被测 PHP 客户端按目标架构运行。
    run(['docker', 'run', '-d', '--pull=never', '--platform', 'linux/amd64', '--name', service,
            '--network', network, '--network-alias', 'mongo', '--memory', '1g',
            '--tmpfs', '/data/db:rw,size=512m', '--tmpfs', '/data/configdb:rw,size=32m',
            '-e', 'MONGO_INITDB_ROOT_USERNAME', '-e', 'MONGO_INITDB_ROOT_PASSWORD',
            mongo_image, '--bind_ip_all', '--nounixsocket', '--wiredTigerCacheSizeGB', '0.25'], env=environment)
    for attempt in range(90):
        logs = run(['docker', 'logs', service])
        if 'MongoDB init process complete; ready for start up.' in logs and logs.count('Waiting for connections') >= 2:
            break
        if attempt == 89:
            raise RuntimeError('临时 MongoDB 未能就绪')
        time.sleep(1)
    print(run(['docker', 'run', '--rm', '--pull=never', '--platform', platform, '--network', network,
                '--memory', '256m', '-v', str(root) + ':/tests:ro', '-e', 'PHP_TEST_MONGO_PASSWORD',
                '--entrypoint', '/usr/local/php/bin/php', image, '-n', '-d', 'extension=' + extension,
                test_script], env=environment), flush=True)
finally:
    subprocess.run(['docker', 'rm', '-f', '-v', service], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['docker', 'network', 'rm', network], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
