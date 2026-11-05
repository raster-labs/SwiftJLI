import hashlib, json, re, subprocess
from pathlib import Path

out = Path(__file__).parent
compiler = Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
sdk = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
products = {
    'baseline': Path('/private/tmp/swiftjli-round3-parser-build/out/Products/Release'),
    'candidate': Path('/private/tmp/swiftjli-round4-build/out/Products/Release')}
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
result = {'method': 'Single public allocated-output decode per fresh process; input and final output retained, no output copy or CryptoKit; Darwin time-l peak RSS. Byte equality is independently gated in paired native benchmark. Same explicit 8 GiB workspace/10 GiB total caps in both builds; worker ceilings stated per case.',
          'timingStatus': 'Provisional host-contention run; elapsed time is not used as an acceptance result.',
          'baselineRevision': '8ae2762710d6279cd92222f5bb5ca95f042f694e',
          'candidateRevision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
          'compilerSHA256': sha(compiler), 'harnessSHA256': sha(out / 'one-shot-memory.swift'),
          'compileCommands': {}, 'objects': {}, 'binaries': {}, 'records': []}
binaries = {}
for label, folder in products.items():
    binary = out / ('one-shot-memory-' + label)
    command = [str(compiler), '-O', '-parse-as-library', '-swift-version', '6', '-strict-concurrency=complete',
               '-target', 'arm64-apple-macos26.0', '-sdk', sdk, '-I', str(folder),
               str(folder / 'SwiftJLI.o'), '-framework', 'Accelerate', str(out / 'one-shot-memory.swift'), '-o', str(binary)]
    result['compileCommands'][label] = command
    result['objects'][label] = {'path': str(folder / 'SwiftJLI.o'), 'sha256': sha(folder / 'SwiftJLI.o')}
    with (out / ('one-shot-memory-' + label + '-compile.log')).open('w') as log:
        subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT)
    binaries[label] = binary
    result['binaries'][label] = {'path': str(binary), 'sha256': sha(binary)}

fixtures = Path('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory')
patterns = Path('/private/tmp/swiftjli-native-matrix-fixtures')
cases = [(fixtures / (profile + '-' + str(size) + '.jpg'), 8)
         for profile in ['dct12', 'rgb8', 'progressiveRGB8'] for size in [512, 2048]]
cases += [(fixtures / ('dct12-' + str(size) + '.jpg'), 1) for size in [512, 2048]]
cases += [(patterns / (profile + '-2048.jpg'), 8) for profile in ['mixed', 'noise']]
pattern = re.compile(rb'\n\s*(\d+)\s+maximum resident set size')
for trial in range(3):
    order = ['baseline', 'candidate'] if trial % 2 == 0 else ['candidate', 'baseline']
    for fixture, workers in cases:
        outputs = {}
        for label in order:
            command = ['/usr/bin/time', '-l', str(binaries[label]), str(fixture), str(workers)]
            completed = subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
            match = pattern.search(completed.stderr)
            if not match:
                raise RuntimeError('Missing maximum RSS: ' + repr(completed.stderr))
            outputs[label] = completed.stdout
            result['records'].append({'trial': trial + 1, 'fixture': fixture.name,
                'fixtureSHA256': sha(fixture), 'workerCeiling': workers, 'label': label,
                'command': command, 'maximumRSSBytes': int(match[1]),
                'outputSummary': completed.stdout.decode().strip()})
        assert outputs['baseline'] == outputs['candidate'], 'Output size/sample summary mismatch'
        (out / 'one-shot-memory.json').write_text(json.dumps(result, indent=2) + '\n')
for label, folder in products.items():
    assert sha(folder / 'SwiftJLI.o') == result['objects'][label]['sha256']
result['status'] = 'passed'
(out / 'one-shot-memory.json').write_text(json.dumps(result, indent=2) + '\n')
print('Passed 10 cases x 3 paired trials; RSS only, full-byte gates in native matrix')
