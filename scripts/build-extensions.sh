#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : build-extensions.sh
# @Desc     : 按 config/extensions.json 编译 PECL 扩展、安装官方 Loader，并记录运行依赖与开关清单。
# @Contact  : admin@dstw.com
set -Eeuo pipefail
manifest() { python3 /build/scripts/manifest.py "$@"; }
variant=${VARIANT_SUFFIX:--}
jobs=${BUILD_JOBS:-4}
base_cflags='-O2 -fstack-protector-strong -std=gnu17 -DOPENSSL_SUPPRESS_DEPRECATED'
export CXXFLAGS='-O2 -fstack-protector-strong -std=gnu++17 -DOPENSSL_SUPPRESS_DEPRECATED'
export LDFLAGS='-Wl,-z,relro,-z,now'
export LD_LIBRARY_PATH=/opt/libiconv/lib
export PATH=/usr/local/php/bin:$PATH
cd /build/.cache/work

echo '校验并应用扩展补丁'
python3 - <<'VERIFY_EXTENSION_PATCHES'
import hashlib
import json
from pathlib import Path
import subprocess
root = Path('/build')
for item in json.loads((root / 'extension-patches.lock.json').read_text())['patches']:
    patch = root / item['file']
    if hashlib.sha256(patch.read_bytes()).hexdigest() != item['sha256']:
        raise SystemExit('扩展补丁摘要不匹配：' + item['file'])
    directory = root / '.cache/work' / item['package']
    if not directory.is_dir():
        continue
    subprocess.run(['git', 'apply', '--check', str(patch)], cwd=directory, check=True)
    subprocess.run(['git', 'apply', '--whitespace=nowarn', str(patch)], cwd=directory, check=True)
    print('已应用扩展补丁：' + item['file'], flush=True)
VERIFY_EXTENSION_PATCHES

echo '为 phpize 配置系统 libtool 2 宏与辅助文件'
php_build=/usr/local/php/lib/php/build
cat /usr/share/aclocal/libtool.m4 /usr/share/aclocal/ltoptions.m4 \
    /usr/share/aclocal/ltsugar.m4 /usr/share/aclocal/ltversion.m4 \
    /usr/share/aclocal/lt~obsolete.m4 > "$php_build/libtool.m4"
cp /usr/share/libtool/build-aux/ltmain.sh "$php_build/ltmain.sh"

while IFS='|' read -r name package extra_cflags configure; do
    [[ -n $name ]] || continue
    echo "编译扩展：$package"
    cd "/build/.cache/work/$package"
    export CFLAGS="$base_cflags${extra_cflags:+ $extra_cflags}"
    phpize
    read -r -a args <<< "$configure"
    ./configure --with-php-config=/usr/local/php/bin/php-config "${args[@]}"
    make -j"$jobs"
    make install
    # 收集扩展包内全部许可文件（含随附第三方库，如 MongoDB 2.x 自带的 C 驱动），保留相对路径。
    mkdir -p "/usr/local/php/share/licenses/$package"
    find . -type f \( -name 'LICENSE*' -o -name 'COPYING*' \) -print0 \
        | tar --null -cf - -T - | tar -xf - -C "/usr/local/php/share/licenses/$package"
done < <(manifest build-rows "$variant")

echo '安装官方 Loader，校验二进制与许可摘要'
mkdir -p /usr/local/ioncube /usr/local/sourceguardian
python3 - <<'INSTALL_LOADERS'
import hashlib
import json
from pathlib import Path
import os
import shutil
work = Path('/build/.cache/work')
# 只安装当前目标架构的官方 Loader（各架构的包与文件摘要分别锁定）。
arch = os.environ.get('TARGETARCH') or 'amd64'
match = lambda item: item.get('arch', arch) == arch
lock = {item['name']: item for item in json.loads(Path('/build/sources.lock.json').read_text())['binary_loaders'] if match(item)}
for loader in [item for item in json.loads(Path('/build/config/extensions.json').read_text())['loaders'] if match(item)]:
    entry = lock[loader['name']]
    source = work / entry['dir'] / entry['file']
    license_file = work / entry['license']
    for path, digest in [(source, entry['sha256']), (license_file, entry['license_sha256'])]:
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit(loader['name'] + ' 或许可摘要不匹配')
    target = Path(loader['path'])
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    for extra in [license_file] + sorted((work / entry['dir']).glob('README*')):
        shutil.copy2(extra, target.parent / extra.name)
    print('已安装 ' + loader['name'] + ' ' + entry['version'] + '：' + str(target), flush=True)
INSTALL_LOADERS

echo '安装 Composer（版本见 config/extensions.json，摘要已在源码准备阶段校验）'
mkdir -p /usr/local/lib/composer
cp "/build/.cache/work/$(manifest composer-file)" /usr/local/lib/composer/composer.phar
chmod 0644 /usr/local/lib/composer/composer.phar

echo '生成入口脚本使用的扩展开关清单'
mkdir -p /usr/local/php/share/lookback
manifest extension-rows > /usr/local/php/share/lookback/extensions.list
cp /build/config/extensions.json /usr/local/php/share/lookback/extensions.json

echo '记录运行时动态库依赖'
scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/php /opt/libiconv /opt/libgd \
    | tr ',' '\n' | sort -u \
    | while IFS= read -r library; do
        [[ -n $library ]] || continue
        if ! find /usr/local/php /opt/libiconv /opt/libgd -name "$library" -print -quit | grep -q .; then
            printf 'so:%s\n' "$library"
        fi
    done > /build/runtime-deps.txt
apk info -v | sort > /usr/local/php/build-apk-packages.txt
/usr/local/php/bin/php -v
echo 'PHP 与扩展编译完成'
