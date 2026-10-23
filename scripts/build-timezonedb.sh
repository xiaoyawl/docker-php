#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : build-timezonedb.sh
# @Desc     : 校验并编译官方时区数据库，默认替换 PHP 内嵌的旧数据。
# @Contact  : admin@dstw.com
set -Eeuo pipefail
cd "$(dirname "$0")/.."
export PATH=/usr/local/php/bin:$PATH
export LD_LIBRARY_PATH=/opt/libiconv/lib
export CFLAGS='-O2 -fstack-protector-strong -std=gnu17'
echo '校验官方时区数据库源码与许可证'
python3 - <<'VERIFY_TIMEZONEDB'
import hashlib,json,tarfile,urllib.request
from pathlib import Path
lock=json.loads(Path('timezonedb.lock.json').read_text())
with urllib.request.urlopen(lock['url'],timeout=120) as response:
    data=response.read()
if len(data)!=lock['size'] or hashlib.sha256(data).hexdigest()!=lock['sha256']:
    raise SystemExit('时区数据库源码摘要或长度不一致')
Path(lock['file']).write_bytes(data)
with tarfile.open(lock['file']) as archive:
    archive.extractall('timezonedb-source',filter='data')
license_file=Path('timezonedb-source')/('timezonedb-'+lock['release'])/'LICENSE'
if hashlib.sha256(license_file.read_bytes()).hexdigest()!=lock['license_sha256']:
    raise SystemExit('时区数据库许可证摘要不一致')
VERIFY_TIMEZONEDB
release=$(python3 -c 'import json; print(json.load(open("timezonedb.lock.json"))["release"])')
cd "timezonedb-source/timezonedb-$release"
phpize
# 旧 phpize 会遗漏 Makefile 的扩展私有 include 路径，显式传入 date 头文件。
./configure --with-php-config=/usr/local/php/bin/php-config --enable-timezonedb \
    CPPFLAGS=-I/usr/local/php/include/php/ext/date/lib
make -j"${BUILD_JOBS:-2}"
make install
mkdir -p "/usr/local/php/share/licenses/timezonedb-$release" /usr/local/php/etc/php.d
cp LICENSE "/usr/local/php/share/licenses/timezonedb-$release/"
printf 'extension=timezonedb.so\n' > /usr/local/php/etc/php.d/15-timezonedb.ini
TZDB_RELEASE=$release php -r 'if (timezone_version_get() !== getenv("TZDB_RELEASE")) {fwrite(STDERR,"时区数据库未生效\n"); exit(1);} echo "时区数据库 ", getenv("TZDB_RELEASE"), " 已生效\n";'
