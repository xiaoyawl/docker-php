#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : verify-services.py
# @Desc     : 在无公网出口和无宿主端口映射的网络中执行数据库与缓存回归。
# @Contact  : admin@dstw.com
import pathlib
import os
import secrets
import subprocess
import sys
import time
import uuid

image, platform = sys.argv[1:3]
service_image = sys.argv[3] if len(sys.argv) > 3 else 'php-test-services:alpine3.24'
suffix = uuid.uuid4().hex[:10]
network, service = 'php-net-'+suffix, 'php-services-'+suffix
root = pathlib.Path(__file__).resolve().parent
test_environment = os.environ.copy()
test_environment['PHP_TEST_DB_PASSWORD'] = secrets.token_hex(16)


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, timeout=60, **kwargs)
    if result.returncode:
        raise RuntimeError('隔离集成命令失败：' + result.stdout + result.stderr)
    return result.stdout


try:
    run(['docker','network','create','--internal',network])
    run(['docker','run','-d','--pull=never','--name',service,'--network',network,'--network-alias','services',
            '--memory','512m','-e','PHP_TEST_DB_PASSWORD',service_image], env=test_environment)
    ready = False
    for attempt in range(90):
        logs = run(['docker','logs',service])
        if '临时数据库与缓存已就绪' in logs:
            ready = True
            break
        time.sleep(1)
    if not ready:
        raise RuntimeError('临时测试服务启动失败')
    print(run(['docker','run','--rm','--pull=never','--platform',platform,'--network',network,
                '--memory','256m','-v',str(root)+':/tests:ro','-e','MEMCACHE=enable','-e','REDIS=enable',
                '-e','PHP_TEST_DB_PASSWORD',image,'php','/tests/services.php'], env=test_environment), flush=True)
finally:
    subprocess.run(['docker','rm','-f',service], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['docker','network','rm',network], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
