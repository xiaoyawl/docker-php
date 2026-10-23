#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : inspect-oci.py
# @Desc     : 验证多架构 OCI 的平台、镜像配置、版本标签及来源/SBOM 证明，并记录索引与各平台摘要。
# @Contact  : admin@dstw.com
import hashlib
import json
import re
from pathlib import Path
import sys
import tarfile

path = Path(sys.argv[1])
output = path.parent
expected_version = sys.argv[2] if len(sys.argv) > 2 else None
# 期望的架构集合取自构建时记录的 platforms.txt（如 linux/amd64,linux/arm64）。
platforms_file = path.parent / 'platforms.txt'
expected_arches = {p.split('/')[1] for p in platforms_file.read_text().strip().split(',')} if platforms_file.exists() else {'amd64'}
php_version = json.loads((Path(__file__).resolve().parent.parent / 'config/extensions.json').read_text())['php']
images = {}
attestations = []
with tarfile.open(path) as archive:
    def read_json(name):
        stream = archive.extractfile(name)
        if stream is None:
            raise SystemExit('OCI 缺少文件：' + name)
        return json.load(stream)

    def blob(digest):
        algorithm, value = digest.split(':', 1)
        if algorithm != 'sha256':
            raise SystemExit('OCI 摘要算法不符合预期')
        name = 'blobs/sha256/' + value
        stream = archive.extractfile(name)
        if stream is None:
            raise SystemExit('OCI 缺少 blob：' + digest)
        data = stream.read()
        if hashlib.sha256(data).hexdigest() != value:
            raise SystemExit('OCI 元数据 blob 摘要不匹配：' + digest)
        return json.loads(data)

    def visit(descriptor):
        manifest = blob(descriptor['digest'])
        if 'manifests' in manifest:
            for child in manifest['manifests']:
                visit(child)
            return
        platform = descriptor.get('platform', {})
        architecture = platform.get('architecture')
        if platform.get('os') == 'linux' and architecture in ('amd64', 'arm64'):
            config = blob(manifest['config']['digest'])
            if config['architecture'] != architecture or config['os'] != 'linux':
                raise SystemExit('OCI 平台与镜像配置不一致')
            labels = config['config'].get('Labels', {})
            version = labels.get('org.opencontainers.image.version', '')
            if not re.fullmatch(re.escape(php_version) + r'\.[0-9]{8}(-[a-z0-9]+)?', version) or (expected_version is not None and version != expected_version):
                raise SystemExit('OCI 镜像版本标签不符合候选版本')
            images[architecture] = {
                'manifest': descriptor['digest'],
                'config': manifest['config']['digest'],
                'compressed_layer_bytes': sum(layer['size'] for layer in manifest['layers']),
                'labels': labels,
                'proofs': []
            }
        elif descriptor.get('annotations', {}).get('vnd.docker.reference.type') == 'attestation-manifest':
            reference = descriptor['annotations']['vnd.docker.reference.digest']
            for layer in manifest['layers']:
                statement = blob(layer['digest'])
                attestations.append((reference, statement))

    index_digests = [descriptor['digest'] for descriptor in read_json('index.json')['manifests']]
    for descriptor in read_json('index.json')['manifests']:
        visit(descriptor)

if set(images) != expected_arches:
    raise SystemExit('OCI 平台不符：期望 ' + ','.join(sorted(expected_arches)) + '，实际 ' + ','.join(sorted(images)))
for architecture, image in images.items():
    for reference, statement in attestations:
        if reference != image['manifest']:
            continue
        kind = statement.get('predicateType', '')
        if 'spdx' in kind:
            name = 'sbom-' + architecture + '.spdx.json'
            document = statement['predicate']
        elif 'slsa' in kind:
            name = 'provenance-' + architecture + '.json'
            document = statement
        else:
            continue
        (output / name).write_text(json.dumps(document, ensure_ascii=False, indent=2) + '\n')
        image['proofs'].append(name)
    if {'sbom-' + architecture + '.spdx.json', 'provenance-' + architecture + '.json'} - set(image['proofs']):
        raise SystemExit('架构缺少来源或 SBOM 证明：' + architecture)

result = {'archive': path.name, 'index_digests': index_digests, 'platforms': images}
(output / 'oci-inspection.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print('OCI（' + ','.join(sorted(images)) + '）配置、元数据摘要、版本标签、provenance 与 SBOM 验证通过。')
print(json.dumps(result, ensure_ascii=False, indent=2))
