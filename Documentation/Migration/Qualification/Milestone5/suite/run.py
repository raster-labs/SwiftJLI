#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Refresh the unchanged four-codec harness with isolated ordinary Linux builds."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--scratch', type=Path, required=True)
parser.add_argument('--image', default='swift:6.4-noble')
parser.add_argument('--output', type=Path, required=True, help='New evidence directory; existing paths are refused')
args = parser.parse_args()
script_dir = Path(__file__).resolve().parent
repo = script_dir.parents[4]
here = args.output.resolve()
try:
    here.mkdir(parents=True, exist_ok=False)
except FileExistsError:
    parser.error('--output must be a new directory; existing evidence will not be overwritten')
scratch = args.scratch.resolve()
scratch.mkdir(parents=True, exist_ok=True)
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

def manifest():
    paths = [repo / 'Package.swift', *sorted((repo / 'Sources').rglob('*.swift')),
             *sorted((repo / 'Examples/SuitePairIntegration').rglob('*.swift')),
             repo / 'Examples/SuitePairIntegration/Package.resolved',
             repo / 'Examples/SuitePairIntegration/Oracle/charls-pgm.cpp',
             *sorted((repo / 'Examples/AllocationProbe/Sources/HeapProbe').rglob('*'))]
    return {str(p.relative_to(repo)): sha(p) for p in paths if p.is_file()}

record = {'status': 'running', 'startedUTC': now(), 'commands': [], 'sourceManifest': manifest(),
          'contractVersion': '0.10.0', 'scratch': str(scratch), 'image': args.image,
          'scope': 'Unsigned greyscale 12/16-bit, six geometries/precisions, twelve ordered codec pairs; no benchmarks or sanitizer allocation figures'}

def save():
    (here / 'execution.json').write_text(json.dumps(record, indent=2) + '\n')

def run(name, command, timeout=1800):
    row = {'name': name, 'argv': list(map(str, command)), 'cwd': str(repo), 'startedUTC': now(),
           'stdout': name + '.stdout.log', 'stderr': name + '.stderr.log'}
    record['commands'].append(row)
    save()
    with (here / row['stdout']).open('w') as output, (here / row['stderr']).open('w') as error:
        result = subprocess.run(row['argv'], cwd=repo, stdout=output, stderr=error, timeout=timeout)
    row.update(exitCode=result.returncode, finishedUTC=now())
    save()
    result.check_returncode()
    return (here / row['stdout']).read_text().strip()

try:
    record['revision'] = run('revision', ['git', 'rev-parse', 'HEAD'])
    record['imageMetadata'] = json.loads(run('image', ['docker', 'image', 'inspect', args.image]))[0]
    record['compiler'] = run('compiler', ['docker', 'run', '--rm', '--network', 'none', args.image, 'swift', '--version'])
    build_container = ['docker', 'run', '--rm', '-v', str(repo) + ':/src:ro', '-v', str(scratch) + ':/work', args.image]
    run('build', build_container + ['swift', 'build', '--package-path', '/src/Examples/SuitePairIntegration',
        '--scratch-path', '/work/build', '--cache-path', '/work/cache', '-c', 'release', '--jobs', '2', '--force-resolved-versions'])
    products = run('products', build_container + ['swift', 'build', '--package-path', '/src/Examples/SuitePairIntegration',
        '--scratch-path', '/work/build', '-c', 'release', '--show-bin-path'])
    binary = products + '/SuitePairIntegration'
    host_binary = scratch / Path(binary).relative_to('/work')
    record['binary'] = {'containerPath': binary, 'hostPath': str(host_binary), 'sha256': sha(host_binary)}
    record['resolvedPeers'] = {}
    for checkout in sorted((scratch / 'build/checkouts').iterdir()):
        if checkout.is_dir():
            record['resolvedPeers'][checkout.name] = run('pin-' + checkout.name, ['git', '-C', checkout, 'rev-parse', 'HEAD'])
    base_run = ['docker', 'run', '--rm', '--network', 'none', '-v', str(scratch) + ':/work']
    run('normal', base_run + [args.image, binary, '/work/normal'])
    run('control', base_run + ['-e', 'SWIFTJLI_COPY_CONTROL=1', args.image, binary, '/work/control'])
    run('heap-verification', ['python3', repo / 'Scripts/verify-cross-codec-heap.py', '--suite',
        '--baseline', here / 'normal.stdout.log', '--control', here / 'control.stdout.log'])
    record['outputs'] = {mode: {p.name: sha(p) for p in sorted((scratch / mode).iterdir())} for mode in ['normal', 'control']}
    if len(record['outputs']['normal']) != 72 or record['outputs']['normal'] != record['outputs']['control']:
        raise ValueError('Expected 72 byte-identical outputs between ordinary and copy-control runs')
    if manifest() != record['sourceManifest']:
        raise ValueError('Shipping/harness source changed during qualification')
    record.update(sourceManifestUnchanged=True, normalHandoffs=72, deliberateCopyControls=72,
                  outputsExactBetweenRuns=True, status='passed')
except BaseException as error:
    record.update(status='failed', error=repr(error))
    raise
finally:
    record['finishedUTC'] = now()
    record['runnerSHA256'] = sha(Path(__file__))
    save()
print(json.dumps({k: record.get(k) for k in ['status', 'revision', 'normalHandoffs', 'deliberateCopyControls', 'resolvedPeers']}))
