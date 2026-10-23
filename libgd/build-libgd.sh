#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-23 00:30:00
# @Author   : LookBack
# @Site     : Asia.DSTW.com
# @Project  : docker-php
# @File     : build-libgd.sh
# @Software : Bash
# @Desc     : 校验并编译带上游旋转修复的 libgd 2.3.3，安装到 /opt/libgd，供 PHP GD 链接。
# @License  : (C) Copyright 2013-2026, DSTW Corporation Limited.
# @Contact  : admin@dstw.com
set -Eeuo pipefail
# 用法：build-libgd.sh <libgd 目录（含 libgd.lock.json、patches/）> <源码缓存目录>
kit=${1:?缺少 libgd 目录}
cache=${2:?缺少源码缓存目录}
jobs=${BUILD_JOBS:-2}
prefix=/opt/libgd
lock=$kit/libgd.lock.json
mkdir -p "$cache"
read -r file url sha256 < <(python3 -c 'import json,sys; s=json.load(open(sys.argv[1]))["source"]; print(s["file"], s["url"], s["sha256"])' "$lock")
if [[ ! -f $cache/$file ]]; then
    echo "下载 libgd 源码：$file"
    python3 -c 'import sys, urllib.request; open(sys.argv[2], "wb").write(urllib.request.urlopen(sys.argv[1], timeout=120).read())' "$url" "$cache/$file.tmp"
    mv "$cache/$file.tmp" "$cache/$file"
fi
echo "$sha256  $cache/$file" | sha256sum -c - >/dev/null || { echo "libgd 源码摘要不匹配：$file" >&2; exit 1; }
work=$(mktemp -d)
tar -xJf "$cache/$file" -C "$work"
cd "$work/libgd-2.3.3"
python3 - "$lock" "$kit" <<'PY'
import hashlib, json, subprocess, sys
lock, kit = sys.argv[1], sys.argv[2]
for item in json.load(open(lock))['patches']:
    path = f"{kit}/{item['file']}"
    if hashlib.sha256(open(path, 'rb').read()).hexdigest() != item['sha256']:
        raise SystemExit('libgd 补丁摘要不匹配：' + item['file'])
    subprocess.run(['git', 'apply', '--check', path], check=True)
    subprocess.run(['git', 'apply', path], check=True)
    print('已应用 libgd 补丁：' + item['file'], flush=True)
PY
# 与 Alpine 3.24 gd-2.3.3-r10 的 configure 选项保持一致，仅安装前缀不同。
./configure --prefix="$prefix" --enable-gd-formats --disable-static >/dev/null
make -j"$jobs" >/dev/null
make install >/dev/null
rm -rf "$prefix/share" "$prefix/lib/"*.la
install -Dm644 COPYING "$prefix/LICENSE-libgd.txt"
cd /
rm -rf "$work"
echo "libgd 2.3.3（含上游旋转修复）已安装到 $prefix"
