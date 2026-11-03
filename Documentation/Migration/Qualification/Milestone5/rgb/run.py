#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Reproduce profile-specific RGB acceptance without changing benchmark thresholds."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--fixtures', type=Path, required=True)
parser.add_argument('--scratch', type=Path, required=True)
parser.add_argument('--djpeg-320', type=Path, required=True)
parser.add_argument('--djpeg-321', type=Path, required=True)
parser.add_argument('--baseline-cli', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True, help='New evidence directory; existing paths are refused')
args = parser.parse_args()
script_dir = Path(__file__).resolve().parent
repo = script_dir.parents[4]
evidence = args.output.resolve()
try:
    evidence.mkdir(parents=True, exist_ok=False)
except FileExistsError:
    parser.error('--output must be a new directory; existing evidence will not be overwritten')
scratch = args.scratch.resolve()
scratch.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
env['PATH'] = str(args.djpeg_321.resolve().parent) + os.pathsep + env['PATH']
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
pins = {
    'rgb8-512.jpg': 'e076975035045954e167a47065e9a139f0b2ff464fc1e0387ac0b205305fe55c',
    'progressiveRGB8-512.jpg': '050be0da3209a4515ac90b45afe0d419e5e99e28c1339d6e25d64a7ffcc3f20b',
}

def source_manifest():
    paths = [repo / 'Package.swift', *sorted((repo / 'Sources').rglob('*.swift'))]
    return {str(path.relative_to(repo)): sha(path) for path in paths}

record = {'status': 'running', 'startedUTC': now(), 'commands': [],
          'contractVersion': '0.10.0', 'sourceManifest': source_manifest(),
          'fixtureSHA256': pins, 'host': platform.platform(),
          'environmentOverrides': {'DEVELOPER_DIR': env['DEVELOPER_DIR'], 'PATHPrefix': str(args.djpeg_321.resolve().parent)},
          'toleranceBasis': 'JPEGDecodeParityTests.swift:36 at ba39fda (2026-10-12) fixes subsampled RGB limit 3. Benchmark limit 2 remains unchanged.',
          'tools': {v: {'path': str(p.resolve()), 'sha256': sha(p)} for v, p in [('3.2.0', args.djpeg_320), ('3.2.1', args.djpeg_321)]}}

def save():
    (evidence / 'execution.json').write_text(json.dumps(record, indent=2) + '\n')

def run(name, command, timeout=900, stdout_path=None):
    log = evidence / (name + '.log')
    row = {'name': name, 'argv': list(map(str, command)), 'cwd': str(repo), 'startedUTC': now(), 'log': log.name}
    record['commands'].append(row)
    save()
    with log.open('w') as stream:
        if stdout_path:
            row['stdoutPath'] = str(stdout_path)
            with stdout_path.open('wb') as output:
                result = subprocess.run(row['argv'], cwd=repo, env=env, stdout=output, stderr=stream, timeout=timeout)
        else:
            result = subprocess.run(row['argv'], cwd=repo, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    row.update(exitCode=result.returncode, finishedUTC=now())
    save()
    result.check_returncode()
    return log.read_text().strip()

try:
    record['revision'] = run('revision', ['git', 'rev-parse', 'HEAD'])
    record['compiler'] = run('compiler', ['xcrun', 'swiftc', '--version'])
    record['xcode'] = run('xcode', ['xcodebuild', '-version'])
    if sha(args.baseline_cli) != '8404f40d5ff8075051965074e56a8e45acc31589f0b57ce2ee521c0d619af86d':
        raise ValueError('Baseline CLI binary pin differs')
    record['baseline'] = {'revision': 'c7791d5635e46f3ef30f1dd1f14d7189e228a5c0',
                          'path': str(args.baseline_cli), 'sha256': sha(args.baseline_cli), 'configuration': 'Release'}
    record['candidateConfiguration'] = 'Debug; public API compiled in Swift 6 mode with complete concurrency checking'
    for filename, expected in pins.items():
        if sha(args.fixtures / filename) != expected:
            raise ValueError('Fixture pin differs: ' + filename)
    run('build', ['swift', 'build', '--package-path', repo / 'Examples/LosslessInterop',
                  '--scratch-path', scratch / 'build', '--jobs', '2'])
    products = Path(run('products', ['swift', 'build', '--package-path', repo / 'Examples/LosslessInterop',
                                    '--scratch-path', scratch / 'build', '--show-bin-path']))
    sdk = run('sdk', ['xcrun', '--sdk', 'macosx', '--show-sdk-path'])
    library = products / 'SwiftJLI.o'
    record['linkedLibrary'] = {'path': str(library), 'sha256': sha(library)}
    binary = scratch / 'subsampled'
    run('compile', ['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '6', '-strict-concurrency=complete',
                    '-target', 'arm64-apple-macos26.0', '-sdk', sdk, '-I', products, library,
                    '-framework', 'Accelerate', script_dir / 'subsampled.swift', '-o', binary])
    record['harnessBinarySHA256'] = sha(binary)
    oracle_dir = scratch / 'references'
    oracle_dir.mkdir(exist_ok=True)
    for filename in pins:
        stem = Path(filename).stem
        for backend in ['scalar', 'automatic']:
            run('baseline-' + stem + '-' + backend,
                [args.baseline_cli, 'decode', '-i', args.fixtures / filename, '-o', '-', '--output-format', 'pnm', '--backend', backend],
                stdout_path=oracle_dir / ('baseline-' + stem + '-' + backend + '.pnm'))
    for version, tool in [('3.2.0', args.djpeg_320), ('3.2.1', args.djpeg_321)]:
        run('djpeg-' + version, [tool, '-version'])
        for filename in pins:
            stem = Path(filename).stem
            run(stem + '-' + version, [tool, '-strict', '-dct', 'int', '-pnm', '-outfile',
                oracle_dir / (stem + '-' + version + '.pnm'), args.fixtures / filename])
    results = json.loads(run('subsampled', [binary, args.fixtures, oracle_dir]))
    (evidence / 'subsampled-results.json').write_text(json.dumps(results, indent=2) + '\n')
    raw_dir = scratch / 'raw-rgb'
    run('raw-rgb', ['python3', repo / 'Scripts/verify-raw-rgb-interop.py', '--output-dir', raw_dir,
                    '--scratch-path', scratch / 'build'])
    shutil.copyfile(raw_dir / 'results.json', evidence / 'raw-rgb-results.json')
    if source_manifest() != record['sourceManifest']:
        raise ValueError('Shipping source changed during qualification')
    record['sourceManifestUnchanged'] = True
    record['subsampledDecodeCases'] = results['decodeCases']
    record['subsampledOracleComparisons'] = results['oracleComparisons']
    record['rawRGBDecodeCases'] = len(json.loads((evidence / 'raw-rgb-results.json').read_text())['results'])
    record['status'] = 'passed'
except BaseException as error:
    record['status'] = 'failed'
    record['error'] = repr(error)
    raise
finally:
    record['finishedUTC'] = now()
    record['harnessSHA256'] = {p.name: sha(p) for p in [script_dir / 'run.py', script_dir / 'subsampled.swift']}
    save()
print(json.dumps({k: record.get(k) for k in ['status', 'revision', 'subsampledDecodeCases', 'subsampledOracleComparisons', 'rawRGBDecodeCases']}))
