#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : build-image.sh
# @Desc     : 在远程 Linux 构建节点按 config/extensions.json 的变体逐个生成 amd64 OCI 镜像，不自动发布。
# @Contact  : admin@dstw.com
set -Eeuo pipefail
[[ $(uname -s) == Linux ]] || { echo '请在指定远程 Linux 构建节点运行，禁止自动改为本机构建。' >&2; exit 1; }
cd "$(dirname "$0")/.."
manifest() { python3 scripts/manifest.py "$@"; }
php_version=$(manifest php-version)
build_date=${BUILD_DATE:-$(TZ=Asia/Shanghai date +%Y%m%d)}
builder=${BUILDX_BUILDER:-default}
docker buildx inspect "$builder" >/dev/null
# 可用 VARIANTS 环境变量只构建指定变体（以空格分隔，无后缀写 -）。
variants=${VARIANTS:-$(manifest variants | tr '\n' ' ')}
for variant in $variants; do
    suffix=${variant#-}
    [[ $variant != - ]] || suffix=''
    label=${suffix:-default}
    image=benyoo/php-alpine:$php_version.$build_date${suffix:+-$suffix}
    output=artifacts/$label
    mkdir -p "$output"
    echo "构建 PHP $php_version 变体 $label：$image"
    docker buildx build --builder "$builder" \
        --platform linux/amd64 \
        --build-arg BUILD_JOBS="${BUILD_JOBS:-2}" \
        --build-arg BUILD_DATE="$build_date" \
        --build-arg PHP_VERSION="$php_version" \
        --build-arg IMAGE_TAG="${image#*:}" \
        --build-arg VARIANT_SUFFIX="$variant" \
        --progress plain --provenance=mode=min --sbom=true \
        --metadata-file "$output/build-metadata.json" \
        --output type=oci,dest="$output/php-$php_version-amd64.oci.tar" \
        -t "$image" .
    (cd "$output" && sha256sum "php-$php_version-amd64.oci.tar" > "php-$php_version-amd64.oci.tar.sha256")
    echo "$image" > "$output/image-tag.txt"
    echo "变体 $label 的 amd64 OCI 镜像已生成：$output/php-$php_version-amd64.oci.tar（尚未推送）"
done
echo '全部变体构建完成，尚未推送镜像仓库。'
