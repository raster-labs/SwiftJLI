#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verify pinned migration origins, exhaustive source/test dispositions and fixtures."""
import argparse
import ast
import re
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--predecessor', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'Documentation/Migration/provenance.json').read_text())
pin = manifest['commit']
def git(*arguments):
    return subprocess.check_output(['git', '-C', str(args.predecessor), *arguments])

inventory = set(git('ls-tree', '-r', '--name-only', pin, '--', 'Sources/JLISwift', 'Tests/JLISwiftTests')
                .decode().splitlines())
accounted = set()
for item in manifest['files']:
    name = item['source']
    if name in accounted:
        raise ValueError(f'Duplicate source disposition: {name}')
    original = git('show', f'{pin}:{name}')
    if hashlib.sha256(original).hexdigest() != item['sourceSHA256']:
        raise ValueError(f'Original source hash differs: {name}')
    if not (root / item['destination']).is_file():
        raise ValueError(f'Migrated destination missing: {name}')
    accounted.add(name)
for item in manifest['retired']:
    if item['source'] in accounted or not item['reason']:
        raise ValueError(f'Invalid retirement: {item}')
    git('cat-file', '-e', f"{pin}:{item['source']}")
    accounted.add(item['source'])
if inventory - accounted:
    raise ValueError(f'Unaccounted source/test paths: {sorted(inventory - accounted)}')
for item in manifest.get('generatedFixtures', []):
    if hashlib.sha256((root / item['path']).read_bytes()).hexdigest() != item['sha256']:
        raise ValueError(f'Generated fixture drift: {item["path"]}')
for item in manifest.get('thirdPartyAssets', []):
    original = (root / item['path']).read_bytes()
    if hashlib.sha256(original).hexdigest() != item['sha256']:
        raise ValueError(f'Third-party fixture drift: {item["path"]}')
    if not (root / item['license']).is_file() or item['copyright'].encode() not in original:
        raise ValueError(f'Third-party copyright/licence missing: {item["path"]}')
    swift = (root / item['embeddedSwift']).read_text()
    literal = re.search(r'static let data: \[UInt8\] = (\[[\s\S]*?\])', swift)
    if not literal or bytes(ast.literal_eval(literal.group(1))) != original:
        raise ValueError(f'Embedded profile differs from licensed bytes: {item["embeddedSwift"]}')
for name in manifest.get('externalRegressionManifests', []):
    fixture_manifest = root / name
    fixtures = json.loads(fixture_manifest.read_text())
    for path, digest in fixtures['files'].items():
        if hashlib.sha256((fixture_manifest.parent / path).read_bytes()).hexdigest() != digest:
            raise ValueError(f'External regression fixture drift: {path}')
    for license in fixtures['licenses']:
        if license not in fixtures['files']:
            raise ValueError(f'External fixture licence is not hash-bound: {license}')
print(f'Provenance passed: {len(inventory)} principal-source/test paths accounted for; '
      f'{len(manifest["files"])} migrated source hashes and {len(manifest.get("generatedFixtures", []))} generated fixtures verified; '
      f'{len(manifest.get("thirdPartyAssets", []))} third-party profiles match their embedded bytes and notices; '
      f'{len(manifest.get("externalRegressionManifests", []))} external regression manifests verified.')
