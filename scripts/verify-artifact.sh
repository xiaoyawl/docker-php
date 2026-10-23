#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : verify-artifact.sh
# @Desc     : 逐个导入各变体的多架构 OCI 文件，对每个架构执行功能回归、扫描与上游 PHPT，并保留运行信息。
# @Contact  : admin@dstw.com
set -Eeuo pipefail
[[ $(uname -s) == Linux ]] || { echo '请在指定远程 Linux 构建节点验收产物。' >&2; exit 1; }
cd "$(dirname "$0")/.."
manifest() { python3 scripts/manifest.py "$@"; }
php_version=$(manifest php-version)
builder=${BUILDX_BUILDER:-dstw-builder}
# 配套服务（MySQL、PostgreSQL、Redis、Memcached、MongoDB）固定在构建节点原生架构运行，只有被测 PHP 镜像按目标架构运行。
services_platform=linux/amd64
mkdir -p artifacts

docker buildx build --builder "$builder" --platform "$services_platform" --load \
    -f tests/Dockerfile.services -t php-test-services:alpine3.24 . > artifacts/build-services.log 2>&1
for key in mongodb mongodb_legacy; do
    image=$(python3 -c 'import json, sys; print(json.load(open("tests/images.lock.json")).get(sys.argv[1], {}).get("image", ""))' "$key")
    [[ -z $image ]] || docker pull --platform "$services_platform" "$image" > "artifacts/$key-pull.log" 2>&1
done

variants=${VARIANTS:-$(manifest variants | tr '\n' ' ')}
for variant in $variants; do
    suffix=${variant#-}
    [[ $variant != - ]] || suffix=''
    label=${suffix:-default}
    out=artifacts/$label
    archive=$out/php-$php_version.oci.tar
    image=$(cat "$out/image-tag.txt")
    platforms=${PLATFORMS:-$(cat "$out/platforms.txt")}
    echo "验收变体 $label：$image（$platforms）"
    (cd "$out" && sha256sum -c "php-$php_version.oci.tar.sha256")
    python3 scripts/inspect-oci.py "$archive" "${image##*:}" > "$out/oci-inspection.log"
    docker load --input "$archive"
    export VARIANT_SUFFIX=$variant
    for platform in ${platforms//,/ }; do
        arch=${platform#linux/}
        export TARGETARCH=$arch
        dir=$out/$arch
        mkdir -p "$dir"
        echo "  验收架构 $platform"
        # 只开启该架构清单中存在的开关；ionCube 与 Xdebug 互斥，运行信息采集时不开启 ionCube。
        all_switches=()
        for switch in $(manifest switches); do
            [[ $switch == IONCUBE ]] || all_switches+=(-e "$switch=enable")
        done
        python3 tests/verify.py "$image" "$platform" > "$dir/verify.log" 2>&1
        python3 tests/verify-security.py "$image" "$platform" > "$dir/security.log" 2>&1
        python3 tests/verify-redis.py "$image" "$platform" > "$dir/redis.log" 2>&1
        docker run --rm --pull=never --platform "$platform" --network none --memory 256m --cpus 2 --pids-limit 128 \
            -v "$PWD/tests:/tests:ro" "$image" python3 /tests/extension-functions.py > "$dir/extensions.log" 2>&1
        python3 tests/verify-mongodb.py "$image" "$platform" > "$dir/mongodb.log" 2>&1
        if python3 -c 'import json, sys; sys.exit(0 if any(e["name"] == "mongo" for e in json.load(open("config/extensions.json"))["extensions"]) else 1)'; then
            python3 tests/verify-mongodb.py "$image" "$platform" mongodb_legacy mongo.so /tests/mongo-legacy.php > "$dir/mongodb-legacy.log" 2>&1
        fi
        python3 tests/verify-services.py "$image" "$platform" > "$dir/verify-services.log" 2>&1
        docker run --rm --pull=never --platform "$platform" --memory 256m --network none "${all_switches[@]}" \
            -v "$PWD/tests:/tests:ro" "$image" php /tests/runtime-info.php > "$dir/runtime.json"
        docker run --rm --pull=never --platform "$platform" --memory 256m --network none \
            "$image" bash -c 'apk info -v | sort' > "$dir/runtime-apk.txt"
        docker run --rm --pull=never --platform "$platform" --memory 256m --network none \
            "$image" php-config --configure-options > "$dir/php-configure.txt"
        docker image inspect --platform "$platform" "$image" \
            --format '{"id":"{{.Id}}","size":{{.Size}},"architecture":"{{.Architecture}}"}' > "$dir/image.json"
        bash scripts/scan-image.sh "$image" "$label-$arch" "$platform" > "$dir/scan.log" 2>&1
        mv "artifacts/trivy-$label-$arch.json" "$dir/trivy.json"
        python3 - "$out" "$arch" <<'PY'
import json
import sys
from pathlib import Path
out, arch = Path(sys.argv[1]), sys.argv[2]
report = json.loads((out / arch / 'trivy.json').read_text())
inspection = json.loads((out / 'oci-inspection.json').read_text())
if report['Metadata']['ImageConfig']['architecture'] != arch:
    raise SystemExit('扫描报告架构与目标平台不匹配')
if report['Metadata']['ImageID'] != inspection['platforms'][arch]['config']:
    raise SystemExit('扫描报告镜像配置摘要与最终 OCI 不匹配')
if not any(item.get('Class') == 'os-pkgs' and item.get('Type') == 'alpine' for item in report.get('Results', [])):
    raise SystemExit('扫描报告缺少 Alpine 系统包结果')
vulnerabilities = [v for item in report['Results'] for v in item.get('Vulnerabilities', [])]
print(arch + ' 扫描核对通过；已报告漏洞数量：' + str(len(vulnerabilities)))
PY
        echo "  变体 $label / $arch 运行回归与扫描完成；漏洞结果须审查 $dir/trivy.json。"
    done
done
if [[ ${SKIP_UPSTREAM_PHPT:-0} != 1 ]]; then
    first=$(manifest variants | head -1)
    first_label=${first#-}
    [[ $first != - ]] || first_label=''
    for platform in $(cat "artifacts/${first_label:-default}/platforms.txt" | tr ',' ' '); do
        echo "运行上游 PHPT 回归：$platform（官方 run-tests.php；失败项须逐项分类）"
        PLATFORM=$platform bash scripts/run-upstream-phpt.sh
    done
fi
echo '全部变体与架构验收完成，镜像尚未推送。'
