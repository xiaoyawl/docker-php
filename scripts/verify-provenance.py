#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : verify-provenance.py
# @Desc     : 验证保存的 Surý 签名、Sources 索引与补丁包摘要链。
# @Contact  : admin@dstw.com
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
php_series = '.'.join(json.loads((root / 'config/extensions.json').read_text())['php'].split('.')[:2])
evidence = root / 'provenance/sury'
fingerprint = '15058500A0235D97F5D10063B188E2B695BD4743'
with tempfile.TemporaryDirectory(prefix='php-source-gpg-') as home:
    result = subprocess.run(['gpg','--homedir',home,'--batch','--no-default-keyring',
            '--keyring',str(evidence/'sury-key.gpg'),'--status-fd','1',
            '--verify',str(evidence/'sury-InRelease')], check=True, capture_output=True, text=True)
    if '[GNUPG:] VALIDSIG '+fingerprint+' ' not in result.stdout:
        raise SystemExit('签名指纹不符合固定值')
index = evidence / 'sury-Sources.gz'
release = (evidence / 'sury-InRelease').read_text()
expected_line = '{} {} main/source/Sources.gz'.format(hashlib.sha256(index.read_bytes()).hexdigest(), index.stat().st_size)
if expected_line not in release:
    raise SystemExit('签名文件中的 Sources 索引摘要不匹配')
stanza = next(part for part in gzip.decompress(index.read_bytes()).decode().split('\n\n') if part.startswith('Package: php' + php_series + '\n'))
lock = json.loads((root/'sources.lock.json').read_text())
package = lock['patch_source']
filename = package['url'].rsplit('/',1)[-1]
if not any(line.split()[:1] == [package['sha256']] and line.split()[2:3] == [filename] for line in stanza.splitlines()):
    raise SystemExit('补丁包摘要与已签名索引不匹配')
print('Surý 签名、Sources 索引与补丁包摘要链验证通过；公钥信任来源为官方 HTTPS 分发。')

for reference in lock.get('reference_patch_sources', []):
    entry = next(part for part in gzip.decompress(index.read_bytes()).decode().split('\n\n') if part.startswith('Package: ' + reference['package'] + '\n'))
    filename = reference['url'].rsplit('/', 1)[-1]
    expected = reference['sha256'] + ' ' + str(reference['size']) + ' ' + filename
    if not any(' '.join(line.split()) == expected for line in entry.splitlines()):
        raise SystemExit('安全修复参考包与已签名源码索引不匹配')
print('额外安全修复参考包的签名索引摘要验证通过。')
