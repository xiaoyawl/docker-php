#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : verify-artifact.sh
# @Desc     : 逐个导入各变体的最终 OCI 文件，执行功能回归与扫描，并保留运行信息。
# @Contact  : admin@dstw.com
set -Eeuo pipefail
[[ $(uname -s) == Linux ]] || { echo '请在指定远程 Linux 构建节点验收产物。' >&2; exit 1; }
cd "$(dirname "$0")/.."
manifest() { python3 scripts/manifest.py "$@"; }
php_version=$(manifest php-version)
builder=${BUILDX_BUILDER:-dstw-builder}
platform=linux/amd64
# 只开启当前版本清单中存在的开关；ionCube 与 Xdebug 互斥，运行信息采集时不开启 ionCube。
all_switches=()
for switch in $(manifest switches); do
    [[ $switch == IONCUBE ]] || all_switches+=(-e "$switch=enable")
done

docker buildx build --builder "$builder" --platform "$platform" --load \
    -f tests/Dockerfile.services -t php-test-services:alpine3.24 . > artifacts/build-services.log 2>&1
for key in mongodb mongodb_legacy; do
    image=$(python3 -c 'import json, sys; print(json.load(open("tests/images.lock.json")).get(sys.argv[1], {}).get("image", ""))' "$key")
    [[ -z $image ]] || docker pull --platform "$platform" "$image" > "artifacts/$key-pull.log" 2>&1
done

variants=${VARIANTS:-$(manifest variants | tr '\n' ' ')}
for variant in $variants; do
    suffix=${variant#-}
    [[ $variant != - ]] || suffix=''
    label=${suffix:-default}
    out=artifacts/$label
    archive=$out/php-$php_version-amd64.oci.tar
    image=$(cat "$out/image-tag.txt")
    echo "验收变体 $label：$image"
    (cd "$out" && sha256sum -c "php-$php_version-amd64.oci.tar.sha256")
    python3 scripts/inspect-oci.py "$archive" "${image##*:}" > "$out/oci-inspection.log"
    docker load --input "$archive"
    export VARIANT_SUFFIX=$variant
    python3 tests/verify.py "$image" "$platform" > "$out/verify.log" 2>&1
    python3 tests/verify-security.py "$image" "$platform" > "$out/security.log" 2>&1
    python3 tests/verify-redis.py "$image" "$platform" > "$out/redis.log" 2>&1
    docker run --rm --pull=never --platform "$platform" --network none --memory 256m --cpus 2 --pids-limit 128 \
        -v "$PWD/tests:/tests:ro" "$image" python3 /tests/extension-functions.py > "$out/extensions.log" 2>&1
    python3 tests/verify-mongodb.py "$image" "$platform" > "$out/mongodb.log" 2>&1
    if python3 -c 'import json, sys; sys.exit(0 if any(e["name"] == "mongo" for e in json.load(open("config/extensions.json"))["extensions"]) else 1)'; then
        python3 tests/verify-mongodb.py "$image" "$platform" mongodb_legacy mongo.so /tests/mongo-legacy.php > "$out/mongodb-legacy.log" 2>&1
    fi
    python3 tests/verify-services.py "$image" "$platform" > "$out/verify-services.log" 2>&1
    docker run --rm --pull=never --platform "$platform" --memory 256m --network none "${all_switches[@]}" \
        -v "$PWD/tests:/tests:ro" "$image" php /tests/runtime-info.php > "$out/runtime.json"
    docker run --rm --pull=never --platform "$platform" --memory 256m --network none \
        "$image" bash -c 'apk info -v | sort' > "$out/runtime-apk.txt"
    docker run --rm --pull=never --platform "$platform" --memory 256m --network none \
        "$image" php-config --configure-options > "$out/php-configure.txt"
    docker image inspect "$image" --format '{"id":"{{.Id}}","size":{{.Size}},"architecture":"{{.Architecture}}"}' \
        > "$out/image.json"
    bash scripts/scan-image.sh "$image" "$label" "$platform" > "$out/scan.log" 2>&1
    mv "artifacts/trivy-$label.json" "$out/trivy.json"
    python3 - "$out" <<'PY'
import json
import sys
from pathlib import Path
out = Path(sys.argv[1])
report = json.loads((out / 'trivy.json').read_text())
inspection = json.loads((out / 'oci-inspection.json').read_text())
if report['Metadata']['ImageConfig']['architecture'] != 'amd64':
    raise SystemExit('扫描报告架构与目标平台不匹配')
if report['Metadata']['ImageID'] != inspection['platforms']['amd64']['config']:
    raise SystemExit('扫描报告镜像配置摘要与最终 OCI 不匹配')
if not any(item.get('Class') == 'os-pkgs' and item.get('Type') == 'alpine' for item in report.get('Results', [])):
    raise SystemExit('扫描报告缺少 Alpine 系统包结果')
vulnerabilities = [v for item in report['Results'] for v in item.get('Vulnerabilities', [])]
print('扫描核对通过；已报告漏洞数量：' + str(len(vulnerabilities)))
PY
    echo "变体 $label 运行回归与扫描完成；漏洞结果须审查 $out/trivy.json。"
done
if [[ ${SKIP_UPSTREAM_PHPT:-0} != 1 ]]; then
    echo '运行上游 PHPT 回归（官方 run-tests.php；失败项须逐项分类）'
    bash scripts/run-upstream-phpt.sh
fi
echo '全部变体 amd64 验收完成，镜像尚未推送。'
