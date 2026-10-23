#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : build-php.sh
# @Desc     : 在容器构建阶段按分支清单编译 PHP 内核与内置扩展（参数见 config/php-configure.txt）。
# @Contact  : admin@dstw.com
set -Eeuo pipefail
manifest() { python3 /build/scripts/manifest.py "$@"; }
php_version=$(manifest php-version)
jobs=${BUILD_JOBS:-2}
export CFLAGS='-O2 -fstack-protector-strong -std=gnu17 -DOPENSSL_SUPPRESS_DEPRECATED'
export CXXFLAGS='-O2 -fstack-protector-strong -std=gnu++17 -DOPENSSL_SUPPRESS_DEPRECATED'
# 补丁版 libgd 安装在 /opt/libgd，以 rpath 固定加载路径，不依赖 LD_LIBRARY_PATH。
export LDFLAGS='-Wl,-z,relro,-z,now -Wl,-rpath,/opt/libgd/lib'
# PHP 7.4 起外部 GD 经 pkg-config 查找 gdlib，需包含补丁版 libgd；5.6 用 --with-gd=/opt/libgd 不受影响。
export PKG_CONFIG_PATH=/opt/libgd/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
export LD_LIBRARY_PATH=/opt/libiconv/lib
cd /build/.cache/work

# GNU libiconv 仅在锁文件包含其源码时编译；目录始终存在，便于运行阶段统一复制。
mkdir -p /opt/libiconv /usr/local/php/share/licenses/php
libiconv_dir=$(find . -maxdepth 1 -type d -name 'libiconv-*' | head -1)
if [[ -n $libiconv_dir ]]; then
    echo "编译 GNU ${libiconv_dir#./}"
    cd "$libiconv_dir"
    ./configure --prefix=/opt/libiconv --disable-static
    make -j"$jobs"
    make install
    mkdir -p /usr/local/php/share/licenses/libiconv
    cp COPYING* /usr/local/php/share/licenses/libiconv/
    cd /build/.cache/work
fi

cd "php-$php_version"
echo "重新生成 PHP $php_version 构建配置"
cat /usr/share/aclocal/pkg.m4 >> acinclude.m4
./buildconf --force
echo "编译 PHP $php_version 与内置扩展"
mapfile -t configure_args < <(manifest configure-args)
./configure "${configure_args[@]}"
make -k -j"$jobs"
make install
# 补丁改动 .l/.re 源文件时，re2c 重新生成的 .c 文件权限为 0600；上游 PHPT 以 nobody 复制源码，需全部可读（仅构建阶段）。
chmod -R a+rX "/build/.cache/work/php-$php_version"
mkdir -p /usr/local/php/etc/php.d
cp php.ini-production /usr/local/php/etc/php.ini
cp php.ini-production /usr/local/php/etc/php.ini-production
cp LICENSE /usr/local/php/share/licenses/php/
echo 'PHP 内核与内置扩展编译完成'
