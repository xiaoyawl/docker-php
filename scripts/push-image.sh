#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-23 07:00:00
# @Author   : Manta
# @Project  : docker-php
# @File     : push-image.sh
# @Software : Bash
# @Desc     : 将已验收的多架构 OCI 归档原样推送到 Docker Hub（保留摘要），建立无后缀别名并核对仓库端摘要。
# @License  : 遵循当前项目已确认的许可证与版权声明
# @Contact  : manta.ops.dstw@gmail.com
set -Eeuo pipefail
# 用法：printf '%s' "$令牌" | DOCKERHUB_USER=benyoo bash scripts/push-image.sh
# 令牌只从标准输入读取，写入临时认证文件，结束后删除；不出现在命令行、环境变量或日志中。
[[ $(uname -s) == Linux ]] || { echo '请在指定远程 Linux 构建节点推送。' >&2; exit 1; }
cd "$(dirname "$0")/.."
manifest() { python3 scripts/manifest.py "$@"; }
php_version=$(manifest php-version)
user=${DOCKERHUB_USER:?请设置 DOCKERHUB_USER}
skopeo_image=quay.io/skopeo/stable:v1.16.1@sha256:94f5c5e26997e2e78c234ec9abf19a391c234b39eb22e6d1210d0b527c97dcc8
token=$(cat)
[[ -n $token ]] || { echo '未从标准输入读到 Docker Hub 令牌' >&2; exit 1; }
auth_dir=$(mktemp -d)
trap 'rm -rf "$auth_dir"' EXIT
chmod 0700 "$auth_dir"
printf '{"auths":{"docker.io":{"auth":"%s"}}}' "$(printf '%s:%s' "$user" "$token" | base64 -w0)" > "$auth_dir/auth.json"
unset token
skopeo() {
    docker run --rm --network host -v "$auth_dir:/auth:ro" -v "$PWD/artifacts:/artifacts:ro" \
        "$skopeo_image" "$1" --authfile /auth/auth.json "${@:2}"
}

variants=$(manifest variants | tr '\n' ' ')
last_label='' last_tag=''
for variant in $variants; do
    suffix=${variant#-}
    [[ $variant != - ]] || suffix=''
    label=${suffix:-default}
    tag=$(cat "artifacts/$label/image-tag.txt")
    expected=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["index_digests"][0])' "artifacts/$label/oci-inspection.json")
    echo "推送变体 $label：$tag（OCI 索引摘要 $expected）"
    skopeo copy --all --preserve-digests "oci-archive:/artifacts/$label/php-$php_version.oci.tar" "docker://docker.io/$tag"
    actual=$(skopeo inspect --raw "docker://docker.io/$tag" | sha256sum | cut -d' ' -f1)
    [[ "sha256:$actual" == "$expected" ]] || { echo "仓库端摘要 sha256:$actual 与已验收 OCI 不一致，停止" >&2; exit 1; }
    echo "  仓库端摘要与已验收 OCI 一致"
    last_label=$label last_tag=$tag
done
# 有 Swoole 后缀的版本，无后缀标签指向清单中最后一个（最高兼容）变体；无后缀版本本身已是该标签。
if [[ $last_tag == *-swoole* ]]; then
    alias=${last_tag%-swoole*}
    echo "建立无后缀别名：$alias → $last_tag"
    skopeo copy --all --preserve-digests "docker://docker.io/$last_tag" "docker://docker.io/$alias"
    [[ $(skopeo inspect --raw "docker://docker.io/$alias" | sha256sum | cut -d' ' -f1) == $(skopeo inspect --raw "docker://docker.io/$last_tag" | sha256sum | cut -d' ' -f1) ]] \
        || { echo '别名摘要与源标签不一致' >&2; exit 1; }
    echo '  别名摘要与源标签一致'
fi
echo "PHP $php_version 全部变体已推送并核对摘要。"
