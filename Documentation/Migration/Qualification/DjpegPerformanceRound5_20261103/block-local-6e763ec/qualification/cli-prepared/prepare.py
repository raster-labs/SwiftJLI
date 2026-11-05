#!/usr/bin/env python3
"""Source-only plan creation: no compiler, codec or benchmark execution."""
from pathlib import Path
import ast
import datetime
import hashlib
import json
import sys

E = Path('/private/tmp/swiftjli-round5-evidence/empty-scratch-fix')
R = E / 'cli-prepared'
W = Path('/private/tmp/swiftjli-round5-empty-scratch-fix')
B = Path('/private/tmp/swiftjli-round5-parser-reservation-release-build/out/Products/Release')
C = Path('/private/tmp/swiftjli-round5-empty-scratch-fix-release-build/out/Products/Release')
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
assert not (R / 'plan.json').exists()
script = W / 'Scripts/benchmark-djpeg.py'
test = W / 'Scripts/test-cli.py'
runner = R / 'run.py'
ast.parse(runner.read_text())
source = json.loads((E / 'source.json').read_text())
release = json.loads((E / 'release-1/command.json').read_text())
assert release['status'] == 'passed' and release['sourceRevision'] == source['sourceRevision']
assert release['exitCode'] == 0 and release['sourceUnchanged'] and release['sourceHashesUnchanged'] and release['compilerUnchanged']
assert release['sourceReceiptSHA256'] == sha(E / 'source.json')
assert release['logSHA256'] == sha(E / 'release-1/tests.log')
oldcli = Path('/private/tmp/swiftjli-round5-evidence/parser-reservation/safety/cli-1/process-checks/report.json')
old = json.loads(oldcli.read_text())
assert old['binary_sha256'] == sha(B / 'swiftjli-cli')
assert old['test_runner_sha256'] == sha(test)
files = {str(W / entry['path']): entry['sha256'] for entry in source['files']}
baseline_preparation = Path('/private/tmp/swiftjli-round5-evidence/flat-small-recovery-guards/prepared-native-runners.json')
for path, value in json.loads(baseline_preparation.read_text())['baselineObjects'].items():
    files[path] = value
additional = [script, test, W / 'Scripts/install-cli.sh', W / 'VERSION', W / 'ManPages/swiftjli-cli.1',
              B / 'swiftjli-cli', C / 'swiftjli-cli', E / 'source.json', E / 'release-1/command.json',
              E / 'release-1/tests.log', C / 'SwiftJLI.o', C / 'SwiftJLIEntropyC.o', baseline_preparation, oldcli,
              Path('/private/tmp/swiftjli-round5-evidence/parser-reservation/full-release-1/command.json'),
              Path(sys.executable).resolve()]
for gate in ['asan', 'tsan']:
    safety = E / (gate + '-1') / 'command.json'
    if safety.exists():
        check = json.loads(safety.read_text())
        assert check['status'] == 'passed' and check['exitCode'] == 0 and check['sourceRevision'] == source['sourceRevision']
        additional += [safety, safety.parent / 'tests.log']
for version in ['3.2.1', '3.2.0']:
    directory = Path('/opt/homebrew/Cellar/jpeg-turbo') / version
    additional += [directory / 'bin/djpeg', directory / 'INSTALL_RECEIPT.json']
    additional += sorted({path.resolve() for path in (directory / 'lib').glob('*.dylib')})
original = Path('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory')
lossless = Path('/private/tmp/swiftjli-native-matrix-fixtures')
cases = {
    'original': [('lossless16', 512), ('lossless16', 2048), ('dct12', 512), ('rgb8', 512), ('progressiveRGB8', 512)],
    'lossless-patterns': [(profile, size) for profile in ['flat', 'ramp', 'noise', 'mixed']
                          for size in [19, 512, 2048, 3072]],
}
for matrix, folder in [('original', original), ('lossless-patterns', lossless)]:
    for profile, size in cases[matrix]:
        additional.append(folder / f'{profile}-{size}.jpg')
        if matrix == 'lossless-patterns':
            additional.append(folder / f'{profile}-{size}.raw')
for path in additional:
    files[str(path)] = sha(path)
assert all(sha(path) == value for path, value in files.items())
plan = {
    'status': 'prepared-not-executed',
    'executionBoundary': 'Prepared after successful pinned Release; no CLI execution until explicit parent CPU grant. Earlier bbc TSan failure and held CLI plan are retained unchanged.',
    'createdUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'baselineRevision': 'ca0c1e874177f429ed199f3ed8ef6ac1315ee66a',
    'candidateRevision': source['sourceRevision'], 'contract': '0.10.0', 'sourceWorktree': str(W),
    'runnerSHA256': sha(runner), 'preparationSHA256': sha(__file__),
    'benchmarkScript': str(script), 'testScript': str(test), 'inputSHA256': files,
    'binarySHA256': {
        'baseline': sha(B / 'swiftjli-cli'), 'candidate': sha(C / 'swiftjli-cli'),
        **{version: sha(Path('/opt/homebrew/Cellar/jpeg-turbo') / version / 'bin/djpeg') for version in ['3.2.1', '3.2.0']},
    },
    'method': 'Unchanged repository benchmark-djpeg.py: process launch + input read + decode + PNM to /dev/null; measured /usr/bin/time -l child RSS and enclosing wall interval. Five warmups, twenty samples, two rounds, original three-engine rotating/reversing order. Correctness precedes timings. Source and binary pins are checked outside timing. No workspace overrides. No compiler or benchmark was executed while preparing this plan.',
    'qualityScope': 'Both Swift builds must retain exact samples/layout and exact PNM. Lossless tolerance0 versus djpeg, all16cases x2 accepted and no resource exclusions. Original5 profiles x2 attempted; lossless16 and dct12 accepted (tolerances0/4); rgb8 and progressiveRGB8 max difference3 exceeds existing tolerance2 and remain excluded without timing. No quality tolerance changes or denominator based on old5f9 rejections. Native full-source oracles and focused safety are separate evidence.',
    'buildAttribution': {
        'candidateRelease': str(E / 'release-1/command.json'),
        'candidateSource': str(E / 'source.json'),
        'candidateProducts': {str(C / name): sha(C / name) for name in ['swiftjli-cli', 'SwiftJLI.o', 'SwiftJLIEntropyC.o']},
        'candidateCLIBuildNote': 'Fresh corrected-child full Release builds these products; source.json and the successful Release receipt/log are pinned. No executable is launched while preparing the plan.',
        'baselineRelease': '/private/tmp/swiftjli-round5-evidence/parser-reservation/full-release-1/command.json',
        'baselinePrior252Checks': str(oldcli),
    },
    'gates': {},
}
python = str(Path(sys.executable).resolve())
benchmark_output = E / 'cli-benchmark-1'
commands = []
for version in ['3.2.1', '3.2.0']:
    for matrix, folder in [('original', original), ('lossless-patterns', lossless)]:
        name = f'{matrix}-{version}'
        output = benchmark_output / (name + '.json')
        command = [python, str(script), '--baseline', str(B / 'swiftjli-cli'), '--candidate', str(C / 'swiftjli-cli'),
                   '--djpeg', str(Path('/opt/homebrew/Cellar/jpeg-turbo') / version / 'bin/djpeg'),
                   '--matrix', matrix, '--fixtures', str(folder), '--output', str(output),
                   '--warmups', '5', '--iterations', '20', '--rounds', '2', '--command-timeout', '60']
        commands.append({'name': name, 'djpegVersion': version, 'fixtures': str(folder), 'command': command,
                         'output': str(output), 'expectedAttemptedCases': [[r, p, s] for r in [1, 2] for p, s in cases[matrix]],
                         'expectedAcceptedRecords': 6 if matrix == 'original' else 32,
                         'expectedExcludedRecords': 4 if matrix == 'original' else 0})
plan['gates']['benchmarks'] = {'outputDirectory': str(benchmark_output), 'commands': commands}
check_output = E / 'cli-checks-1'
report = check_output / 'process-checks/report.json'
plan['gates']['cli-checks'] = {'outputDirectory': str(check_output), 'commands': [
    {'name': 'process-checks', 'command': [python, str(test), '--binary', str(C / 'swiftjli-cli'), '--output', str(report.parent)],
     'output': str(report)}]}
(R / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
print(json.dumps({'prepared': str(R / 'plan.json'), 'runnerSHA256': sha(runner),
                  'planSHA256': sha(R / 'plan.json'), 'files': len(files),
                  'binarySHA256': plan['binarySHA256'], 'status': plan['status']}, indent=2))
