#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Measure the host-callback correction against its frozen SwiftJLI baseline.

This is a before/after regression experiment, not a djpeg speed comparison.
Every accepted encode/decode output must match the baseline byte for byte.
The independent JPEG profile qualification and stricter historical djpeg
benchmark exclusions remain separate and unchanged.
"""
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
for name in ('baseline', 'candidate', 'fixtures', 'patterns', 'output', 'build-metadata'):
    parser.add_argument('--' + name, type=Path, required=True)
parser.add_argument('--rounds', type=int, default=2)
parser.add_argument('--case', action='append', help='Named case for a targeted follow-up')
args = parser.parse_args()
if args.rounds < 2:
    parser.error('At least two rounds are required')
script_dir = Path(__file__).resolve().parent
root = script_dir.parents[4]
spec = importlib.util.spec_from_file_location('benchmark', root / 'Scripts/benchmark-djpeg.py')
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
source_hashes = lambda: {str(p.relative_to(root)): sha(p) for p in sorted((root / 'Sources').rglob('*.swift'))}
provenance_path = script_dir / 'fixture-provenance.json'
provenance = json.loads(provenance_path.read_text())
build_metadata = json.loads(args.build_metadata.read_text())
cases = [(name, args.fixtures / (name + '.jpg'), mode) for name, mode in (
    ('lossless16-512', 'lossless'), ('lossless16-2048', 'lossless'),
    ('dct12-512', 'lossy'), ('rgb8-512', 'lossy'), ('progressiveRGB8-512', 'lossy'))]
cases.append(('flat-19', args.patterns / 'flat-19.jpg', 'lossless'))
if args.case:
    if not set(args.case) <= {name for name, _, _ in cases}:
        parser.error('Unknown selected case')
    cases = [case for case in cases if case[0] in args.case]
output = args.output.resolve()
try:
    output.mkdir(parents=True, exist_ok=False)
except FileExistsError:
    parser.error('Choose a fresh --output directory; retained evidence is immutable')
paths = {key: getattr(args, key).resolve() for key in ('baseline', 'candidate')}
fixture_hashes = {name: sha(fixture) for name, fixture, _ in cases}
record = {'status': 'running', 'startedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'method': __doc__, 'warmups': 5, 'timedIterations': 20, 'rounds': args.rounds,
          'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
          'sourceSHA256': source_hashes(), 'binarySHA256': {key: sha(p) for key, p in paths.items()},
          'runnerSHA256': sha(Path(__file__)), 'benchmarkHelperSHA256': sha(root / 'Scripts/benchmark-djpeg.py'),
          'buildMetadata': build_metadata, 'buildMetadataSHA256': sha(args.build_metadata),
          'fixtureProvenance': provenance, 'fixtureProvenanceSHA256': sha(provenance_path),
          'inputFixtureSHA256': fixture_hashes,
          'arguments': {k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()},
          'commandCount': 0, 'records': [], 'environment': []}
rss_pattern = re.compile(rb'\n\s*(\d+)\s+maximum resident set size')

def save():
    (output / 'results.json').write_text(json.dumps(record, indent=2) + '\n')

def environment(stage):
    for command in (['xcrun', 'swift', '--version'], ['sw_vers'], ['uname', '-m'],
                    ['pmset', '-g', 'batt'], ['pmset', '-g', 'therm'],
                    ['ps', '-axo', 'pid,pcpu,comm']):
        result = subprocess.run(command, text=True, capture_output=True)
        record['environment'].append({'stage': stage, 'argv': command, 'exitCode': result.returncode,
                                      'stdout': result.stdout, 'stderr': result.stderr})
        result.check_returncode()

def run(command, capture=False, measured=False):
    command = list(map(str, command))
    invoked = ['/usr/bin/time', '-l', *command] if measured else command
    record['activeCommand'] = invoked
    started = time.perf_counter_ns()
    result = benchmark.run_bounded(invoked, 60, stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
    elapsed = (time.perf_counter_ns() - started) / 1e9
    record['commandCount'] += 1
    if measured:
        match = rss_pattern.search(result.stderr)
        if not match:
            raise RuntimeError('Darwin peak RSS missing')
        return elapsed, int(match[1])
    if result.stderr:
        raise RuntimeError('Unexpected CLI diagnostics: ' + result.stderr.decode(errors='replace'))
    return result.stdout

try:
    if build_metadata['binarySHA256'] != record['binarySHA256']:
        raise RuntimeError('Executable hashes do not match the supplied build metadata')
    if build_metadata['sourceSHA256']['candidate'] != record['sourceSHA256']:
        raise RuntimeError('Candidate sources do not match the supplied build metadata')
    for name, actual in fixture_hashes.items():
        if actual != provenance['fixtures'][name]['sha256']:
            raise RuntimeError('Fixture differs from retained provenance: ' + name)
    shutil.copyfile(__file__, output / 'run-executed.py')
    save()
    environment('before')
    for round_number in range(1, args.rounds + 1):
        for name, fixture, mode in cases:
            decode = {key: [path, 'decode', '-i', fixture, '-o', '-', '--output-format', 'pnm']
                      for key, path in paths.items()}
            baseline_pixels = run(decode['baseline'], capture=True)
            candidate_pixels = run(decode['candidate'], capture=True)
            if baseline_pixels != candidate_pixels:
                raise RuntimeError('Decoded bytes differ: ' + name)
            layout, _ = benchmark.parse_pnm(baseline_pixels)
            pnm = output / (name + '.pnm')
            pnm.write_bytes(baseline_pixels)
            encode = {key: [path, 'encode', '-i', pnm, '-o', '-', '--input-format', 'pnm',
                            '--output-format', 'jpeg',
                            '--mode', mode, *(['--quality', '85'] if mode == 'lossy' else []),
                            *(['--progressive', 'successive-approximation']
                              if name == 'progressiveRGB8-512' else [])]
                      for key, path in paths.items()}
            baseline_encoded = run(encode['baseline'], capture=True)
            if baseline_encoded != run(encode['candidate'], capture=True):
                raise RuntimeError('Encoded bytes differ: ' + name)
            for operation, commands, expected in (('decode', decode, baseline_pixels),
                                                  ('encode', encode, baseline_encoded)):
                timings, rss = {key: [] for key in paths}, {key: [] for key in paths}
                for iteration in range(-5, 20):
                    order = list(paths)
                    if (iteration + round_number) % 2:
                        order.reverse()
                    for key in order:
                        if iteration < 0:
                            run(commands[key])
                        else:
                            duration, peak = run(commands[key], measured=True)
                            timings[key].append(duration)
                            rss[key].append(peak)
                row = {'round': round_number, 'case': name, 'operation': operation, 'layout': layout,
                       'encoderScanMode': ('successive-approximation' if name == 'progressiveRGB8-512'
                                           else 'sequential') if mode == 'lossy' and operation == 'encode' else None,
                       'inputJPEG_SHA256': sha(fixture), 'inputPNM_SHA256': sha(pnm),
                       'encodedBytes': len(baseline_encoded) if operation == 'encode' else fixture.stat().st_size,
                       'baselineCandidateExactBytes': True, 'outputSHA256': hashlib.sha256(expected).hexdigest(),
                       'commands': {key: list(map(str, command)) for key, command in commands.items()}}
                for key in paths:
                    row[key] = {'elapsedSeconds': benchmark.stats(timings[key]),
                                'peakRSSBytes': benchmark.stats(rss[key]),
                                'medianPixelsPerSecond': layout[1] * layout[2] / statistics.median(timings[key])}
                record['records'].append(row)
                save()
                print(f'{round_number} {name} {operation}: ' + ', '.join(
                    f'{key} {statistics.median(timings[key])*1000:.3f} ms' for key in paths), flush=True)
    environment('after')
    if source_hashes() != record['sourceSHA256'] or any(sha(p) != record['binarySHA256'][key] for key, p in paths.items()):
        raise RuntimeError('Source or executable changed during comparison')
    if {name: sha(fixture) for name, fixture, _ in cases} != fixture_hashes:
        raise RuntimeError('Input fixture changed during comparison')
    for path, expected in ((Path(__file__), record['runnerSHA256']),
                           (root / 'Scripts/benchmark-djpeg.py', record['benchmarkHelperSHA256']),
                           (args.build_metadata, record['buildMetadataSHA256']),
                           (provenance_path, record['fixtureProvenanceSHA256'])):
        if sha(path) != expected:
            raise RuntimeError('Measurement harness or provenance changed during comparison: ' + str(path))
    record.update(status='measured_outputs_exact', finishedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat())
    record.pop('activeCommand', None)
except BaseException as error:
    record.update(status='failed', error=repr(error))
    if isinstance(error, subprocess.CalledProcessError):
        record['failedCommand'] = {'argv': error.cmd, 'exitCode': error.returncode,
                                   'stderr': (error.stderr or b'').decode(errors='replace')}
    raise
finally:
    save()
