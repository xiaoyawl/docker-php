#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time: 2026-10-22
# @Author: LookBack
# @Project: docker-php
# @File: modern-tls-fixtures.sh
# @Desc: 在一次性断网测试容器执行本版TLS正负控制，不修改产品安全级别。
set -Eeuo pipefail
python3 /tests/tls-security.py
