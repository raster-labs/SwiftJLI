import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
from provenance import import_snapshot, unchanged

parser = argparse.ArgumentParser()
parser.add_argument('--compile-only', action='store_true')
parser.add_argument('--run-only', action='store_true')
parser.add_argument('--candidate-products', type=Path, required=True)
parser.add_argument('--baseline-products', type=Path, default=Path('/private/tmp/swiftjli-round5-5f9e1cf-fma-baseline/out/Products/Release'))
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path('/private/tmp')
compiler = Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
sdk = Path('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk')
harness = root / 'swiftjli-native-matrix.swift'
fixtures = root / 'swiftjli-native-matrix-fixtures'
output = args.output
output.parent.mkdir(parents=True,exist_ok=True)
if args.run_only and args.compile_only: raise SystemExit('Mutually exclusive modes')
if output.exists() and not args.run_only: raise SystemExit('Refusing to overwrite retained results')

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def command_text(command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT).strip()

products = {'baseline': args.baseline_products, 'candidate': args.candidate_products}
binaries = {name: output.with_name(output.stem + '-' + name) for name in products}
if args.run_only:
    result = json.loads(output.read_text())
    if result.get('status') != 'compiled' or result.get('matrix'):
        raise SystemExit('Run-only requires an unused compiled receipt')
else:
    result = {
        'status': 'compiling', 'startedUTC': now(),
        'baselineRevision': '5f9e1cf50db4eee4d5439f80602f3dfe9f24b0cd',
        'candidateRevision': 'ba2771eb3393c703fba106082720d9987c0594e9', 'timingStatus': 'Advisory shared host; dedicated agent CPU window required; all samples retained',
        'compilerPath': str(compiler), 'compilerRealPath': str(compiler.resolve()),
        'compilerSHA256': sha(compiler), 'compilerVersion': command_text([str(compiler), '--version']),
        'xcodeVersion': command_text(['xcodebuild', '-version']),
        'sdkPath': str(sdk), 'sdkRealPath': str(sdk.resolve()),
        'harnessPath': str(harness), 'harnessSHA256': sha(harness),
        'runnerSHA256': sha(Path(__file__)), 'provenanceSHA256': sha(Path(__file__).with_name('provenance.py')),
        'importedArtifacts': {name: import_snapshot(folder) for name, folder in products.items()},
        'method': 'Public SwiftJLI.Decoder.decode with allocated output; identical JPEG bytes; exact full-output comparison against source before timing; 5 warmups then20 individual decode samples per case;16 cases;2 rounds with binary order reversed. Input file reads and correctness comparisons outside timing.',
        'fixtureSHA256': {str(path.name): sha(path) for path in sorted(fixtures.glob('*'))},
        'auxiliaryObjects': {}, 'linkedObjects': {}, 'binarySHA256': {}, 'compileCommands': {}, 'matrix': [],
        'earlierExperiments': 'All prior rejected and unselected experiment records remain separate. This matrix compares composed source against retained qualified5f9 products.'
    }
    for name, folder in products.items():
        object_path = folder / 'SwiftJLI.o'
        object_hash = sha(object_path)
        command = [str(compiler), '-O', '-parse-as-library', '-target', 'arm64-apple-macos26.0',
                   '-sdk', str(sdk), '-I', str(folder), str(object_path), '-framework', 'Accelerate',
                   str(harness), '-o', str(binaries[name])]
        extra = folder / 'SwiftJLIEntropyC.o'
        if extra.is_file():
            modulemap = folder.parent.parent / 'Intermediates.noindex/GeneratedModuleMaps/SwiftJLIEntropyC.modulemap'
            command += [str(extra), '-Xcc', '-fmodule-map-file=' + str(modulemap)]
            result['auxiliaryObjects'][name] = {'path': str(extra), 'sha256': sha(extra), 'modulemap': str(modulemap), 'modulemapSHA256': sha(modulemap)}
        log = output.with_name(output.stem + '-' + name + '-compile.log')
        with log.open('w') as stream:
            subprocess.run(command, check=True, stdout=stream, stderr=subprocess.STDOUT)
        assert sha(object_path) == object_hash, 'Object changed during link'
        result['linkedObjects'][name] = {'path': str(object_path), 'sha256': object_hash}
        result['binarySHA256'][name] = sha(binaries[name])
        result['compileCommands'][name] = command
    assert sha(compiler) == result['compilerSHA256'], 'Compiler changed during link'
    result['status'] = 'compiled'
    result['compiledUTC'] = now()
    output.write_text(json.dumps(result, indent=2) + '\n')
    print('Both public API harnesses compiled using', result['compilerVersion'], flush=True)
if args.compile_only:
    raise SystemExit(0)

assert sha(compiler) == result['compilerSHA256'], 'Compiler changed before benchmark'
assert sha(harness) == result['harnessSHA256'], 'Harness changed before benchmark'
for name, binary in binaries.items():
    assert sha(binary) == result['binarySHA256'][name], 'Binary changed before benchmark'
for round_number in [1, 2]:
    for name in products:
        log = output.with_name(output.stem + '-' + name + '-round' + str(round_number) + '.jsonl')
        if log.exists() or log.with_suffix('.stderr.log').exists():
            raise SystemExit('Refusing to overwrite retained round logs')
result['matrix'] = []
result['status'] = 'running'
result['timingStartedUTC'] = now()
for round_number in [1, 2]:
    order = ['baseline', 'candidate'] if round_number == 1 else ['candidate', 'baseline']
    for name in order:
        command = [str(binaries[name]), 'benchmark', str(fixtures)]
        log = output.with_name(output.stem + '-' + name + '-round' + str(round_number) + '.jsonl')
        with log.open('w') as stream, log.with_suffix('.stderr.log').open('w') as errors:
            subprocess.run(command, check=True, stdout=stream, stderr=errors)
        records = [json.loads(line) for line in log.read_text().splitlines()]
        assert len(records) == 16 and all(r['pixelExact'] and len(r['samplesSeconds']) == 20 for r in records)
        result['matrix'].append({'round': round_number, 'binary': name, 'command': command, 'records': records})
        output.write_text(json.dumps(result, indent=2) + '\n')
        print('Completed', name, 'round', round_number, '16 exact cases', flush=True)
assert sha(compiler) == result['compilerSHA256'], 'Compiler changed during benchmark'
result['auxiliaryObjectsUnchanged'] = all(sha(v['path']) == v['sha256'] for v in result['auxiliaryObjects'].values())
result['objectsUnchanged'] = all(sha(v['path']) == v['sha256'] for v in result['linkedObjects'].values())
result['binariesUnchanged'] = all(sha(v) == result['binarySHA256'][k] for k, v in binaries.items())
result['harnessUnchanged'] = sha(harness) == result['harnessSHA256']
result['runnerUnchanged'] = sha(Path(__file__)) == result['runnerSHA256']
result['provenanceUnchanged'] = sha(Path(__file__).with_name('provenance.py')) == result['provenanceSHA256']
result['importsUnchanged'] = all(unchanged(v) for v in result['importedArtifacts'].values())
result['fixturesUnchanged'] = all(sha(fixtures / p) == v for p, v in result['fixtureSHA256'].items())
result['status'] = 'complete' if all(result[k] for k in ['objectsUnchanged', 'auxiliaryObjectsUnchanged', 'importsUnchanged', 'fixturesUnchanged', 'binariesUnchanged', 'harnessUnchanged', 'runnerUnchanged', 'provenanceUnchanged']) else 'failed-artifact-verification'
result['finishedUTC'] = now()
output.write_text(json.dumps(result, indent=2) + '\n')

assert result['status'] == 'complete', 'Artifact verification failed'
