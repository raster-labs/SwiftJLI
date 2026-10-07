#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verify pinned migration origins, exhaustive source/test dispositions and fixtures."""
import argparse
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
print(f'Provenance passed: {len(inventory)} principal-source/test paths accounted for; '
      f'{len(manifest["files"])} migrated source hashes and {len(manifest.get("generatedFixtures", []))} generated fixtures verified.')
