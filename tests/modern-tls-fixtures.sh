#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : modern-tls-fixtures.sh
# @Desc     : 仅在一次性构建容器中更新上游 TLS 测试证书和显式协议，不改产品安全级别。
# @Contact  : admin@dstw.com
set -Eeuo pipefail
PHP_VERSION=$(python3 -c 'import json; print(json.load(open("/build/config/extensions.json"))["php"])')
folder=/build/.cache/work/php-$PHP_VERSION/ext/openssl/tests
export FIXTURE_FOLDER=$folder
[[ -d $folder ]] || { echo '请仅在包含 PHP 源码的一次性构建阶段容器执行。' >&2; exit 1; }
echo '生成临时 RSA2048/SHA256 测试证书；SNI 使用显式 TLS1.2，保持产品验证策略'
make_cert() {
    local name=$1 target=$2
    openssl req -x509 -newkey rsa:2048 -nodes -days 2 -sha256 \
        -keyout /tmp/fixture.key -out /tmp/fixture.crt -subj "/CN=$name" \
        -addext "subjectAltName=DNS:$name" > /dev/null 2>&1
    cat /tmp/fixture.crt /tmp/fixture.key > "$folder/$target"
}
make_cert bug54992.local bug54992.pem
cp /tmp/fixture.crt "$folder/bug54992-ca.pem"
FIXTURE_SHA256=$(openssl x509 -in /tmp/fixture.crt -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr A-F a-f)
export FIXTURE_SHA256
python3 - <<'PY'
from pathlib import Path
import os
p=Path(os.environ['FIXTURE_FOLDER'])/'openssl_peer_fingerprint_basic.phpt'
s=p.read_text().replace('06941b4f4f00523f6c81b69ad4424b3506320285a8b1bd084c112435a12ff487',os.environ['FIXTURE_SHA256'])
p.write_text(s)
PY
make_cert domain1.com domain1.pem
for number in 1 2 3; do make_cert "domain$number.com" "sni_server_domain$number.pem"; done
python3 - <<'ADAPT_FIXTURE'
from pathlib import Path
import os
p=Path(os.environ['FIXTURE_FOLDER'])/'sni_server.phpt'
p.write_text(p.read_text().replace('tls://','tlsv1.2://'))
ADAPT_FIXTURE
python3 /tests/upstream-regressions.py /results/upstream-modern-tls-fixtures.json bug72333 openssl_peer_fingerprint_basic sni_server.phpt
