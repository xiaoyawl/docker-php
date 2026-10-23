#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : verify-redis.py
# @Desc     : 在无公网出口及无宿主端口映射的网络中验证 Redis 扩展兼容性。
# @Contact  : admin@dstw.com
from pathlib import Path
import subprocess
import sys
import time
import uuid

image = sys.argv[1]
platform = sys.argv[2] if len(sys.argv) > 2 else 'linux/amd64'
services_image = sys.argv[3] if len(sys.argv) > 3 else 'php-test-services:alpine3.24'
suffix = uuid.uuid4().hex[:10]
network, service = 'php-redis-net-' + suffix, 'php-redis-' + suffix
tests = Path(__file__).resolve().parent


def run(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise RuntimeError('Redis 隔离验证命令失败：' + result.stdout + result.stderr)
    return result.stdout


try:
    run(['docker', 'network', 'create', '--internal', network])
    run(['docker', 'run', '-d', '--pull=never', '--name', service, '--network', network,
            '--network-alias', 'services', '--memory', '128m', '--cpus', '1', '--pids-limit', '64',
            '--entrypoint', 'redis-server', services_image,
            '--bind', '0.0.0.0', '--protected-mode', 'no', '--save', '', '--appendonly', 'no'])
    for attempt in range(30):
        if 'Ready to accept connections' in run(['docker', 'logs', service]):
            break
        time.sleep(0.3)
    else:
        raise RuntimeError('隔离 Redis 服务未就绪')
    print(run(['docker', 'run', '--rm', '--pull=never', '--platform', platform, '--network', network,
                '--memory', '256m', '--cpus', '2', '--pids-limit', '64',
                '-v', str(tests) + ':/tests:ro', '-e', 'REDIS=enable',
                image, 'php', '/tests/redis-compat.php']).strip(), flush=True)
finally:
    subprocess.run(['docker', 'rm', '-f', service], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['docker', 'network', 'rm', network], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
