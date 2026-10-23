#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : scan-image.sh
# @Desc     : 使用固定版本与摘要的 Trivy 扫描本机候选镜像，保留完整结果。
# @Contact  : admin@dstw.com
set -Eeuo pipefail
cd "$(dirname "$0")/.."
image=${1:?请指定已载入构建节点的镜像}
report=${2:-image}
platform=${3:-}
[[ $report =~ ^[A-Za-z0-9_.-]+$ ]] || { echo '报告名称格式无效' >&2; exit 1; }
mkdir -p artifacts .cache/trivy
platform_args=()
[[ -z $platform ]] || platform_args=(--platform "$platform")
# Docker socket 的多架构读取可能返回宿主平台；先导出指定平台再扫描，避免架构串用。
archive="$PWD/.cache/trivy-image-$report.tar"
docker image save "${platform_args[@]}" --output "$archive" "$image"
docker run --rm -v "$archive:/scan-image.tar:ro" \
    -v "$PWD/.cache/trivy:/root/.cache/trivy" -v "$PWD/artifacts:/reports" \
    aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c \
    image --input /scan-image.tar --scanners vuln --no-progress --timeout 10m \
    --format json --output "/reports/trivy-$report.json" "$image"
echo "扫描报告已保存：artifacts/trivy-$report.json；需结合源码回补证据审查结果。"
