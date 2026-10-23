#!/bin/sh
# -*- coding: utf-8 -*-
# @Time     : 2026-10-23 03:20:00
# @Author   : LookBack
# @Site     : Asia.DSTW.com
# @Project  : docker-php
# @File     : composer.sh
# @Software : Shell
# @Desc     : Composer 启动包装：仅为 Composer 自身进程清空 disable_functions，业务 FPM/CLI 仍保持禁用。
# @License  : (C) Copyright 2013-2026, DSTW Corporation Limited.
# @Contact  : admin@dstw.com
exec /usr/local/php/bin/php -d disable_functions= /usr/local/lib/composer/composer.phar "$@"
