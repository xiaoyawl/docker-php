#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-23 03:30:00
# @Author   : LookBack
# @Site     : Asia.DSTW.com
# @Project  : docker-php
# @File     : run-upstream-phpt.sh
# @Software : Bash
# @Desc     : 导出构建阶段镜像，以非 root、断网方式运行官方 run-tests.php 上游 PHPT 回归。
# @License  : (C) Copyright 2013-2026, DSTW Corporation Limited.
# @Contact  : admin@dstw.com
set -Eeuo pipefail
[[ $(uname -s) == Linux ]] || { echo '请在指定远程 Linux 构建节点运行。' >&2; exit 1; }
cd "$(dirname "$0")/.."
manifest() { python3 scripts/manifest.py "$@"; }
php_version=$(manifest php-version)
# 上游 PHPT 与 Swoole 变体无关，默认使用清单中的第一个变体。
variant=${VARIANT:-$(manifest variants | head -1)}
suffix=${variant#-}
[[ $variant != - ]] || suffix=''
label=${suffix:-default}
# 目标架构：默认 amd64；arm64 经 QEMU 运行，耗时明显更长。
platform=${PLATFORM:-linux/amd64}
arch=${platform#linux/}
image=lookback-php-build:$php_version-$label-$arch
out=$PWD/artifacts/$label/$arch/upstream-phpt
rm -rf "$out"
mkdir -p "$out"
chmod 0777 "$out"
echo "导出构建阶段镜像：$image（复用构建缓存）"
docker buildx build --builder "${BUILDX_BUILDER:-dstw-builder}" --platform "$platform" --target build \
    --build-arg BUILD_JOBS="${BUILD_JOBS:-2}" --build-arg VARIANT_SUFFIX="$variant" \
    --load -t "$image" . > "$out/build-stage.log" 2>&1
echo '以 nobody 用户、断网运行官方 run-tests.php'
docker run --rm --platform "$platform" -e PHPT_TIMEOUT="${PHPT_TIMEOUT:-$([[ $arch == amd64 ]] && echo 7200 || echo 43200)}" --network none --user 65534:65534 --memory 3g --tmpfs /tmp:rw,exec,size=1g \
    --tmpfs /work:rw,exec,size=4g,uid=65534,gid=65534 \
    -v "$PWD/tests:/tests:ro" -v "$out:/results" "$image" python3 /tests/upstream-phpt.py /results
echo "上游 PHPT 结果：$out/upstream-phpt.json"
