import argparse, pathlib, subprocess, json, hashlib, datetime, os
p = pathlib.Path(__file__).parent
parser = argparse.ArgumentParser()
parser.add_argument('--compile-only', action='store_true')
parser.add_argument('--run-only', action='store_true')
args = parser.parse_args()
compiler = pathlib.Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
sdk = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
sha = lambda file: hashlib.sha256(pathlib.Path(file).read_bytes()).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
output = p / 'targeted-results.json'
products = {'baseline': pathlib.Path('/private/tmp/swiftjli-round5-704ddae-products'),
            'candidate': pathlib.Path('/private/tmp/swiftjli-round5-c-ac-leaf-build/out/Products/Release')}
if args.run_only:
    result = json.loads(output.read_text())
else:
    result = {'reason': 'Resolve repeated lossless regressions using immediate per-case pairing; original two-round matrix retained unchanged.',
              'baselineRevision': '704ddae1bafea95d8a48c01ce35887c5b6413c0d',
              'candidateRevision': '3a5ef320c04fff03561a69b705355c0e9da2fc31',
              'timingStatus': 'Advisory shared host; no concurrent agent CPU jobs; every host snapshot and timing sample retained.',
              'compilerSHA256': sha(compiler), 'compilerVersion': subprocess.check_output([str(compiler), '--version'], text=True, stderr=subprocess.STDOUT),
              'startedUTC': now(), 'harnessSHA256': sha(p / 'targeted.swift'), 'runnerSHA256': sha(__file__),
              'cases': ['ramp-2048', 'ramp-3072', 'noise-19', 'noise-512', 'flat-2048', 'noise-2048'],
              'rounds': 4, 'warmups': 5, 'samplesPerCase': 20, 'commands': [], 'objects': {}, 'records': []}
    for name, folder in products.items():
        obj = folder / 'SwiftJLI.o'
        command = [str(compiler), '-O', '-parse-as-library', '-target', 'arm64-apple-macos26.0',
                   '-sdk', sdk, '-I', str(folder), str(obj), '-framework', 'Accelerate',
                   str(p / 'targeted.swift'), '-o', str(p / ('targeted-' + name))]
        result['objects'][name] = {'path': str(obj), 'sha256': sha(obj)}
        extra = folder / 'SwiftJLIEntropyC.o'
        if extra.is_file():
            modulemap = folder.parent.parent / 'Intermediates.noindex/GeneratedModuleMaps/SwiftJLIEntropyC.modulemap'
            command += [str(extra), '-Xcc', '-fmodule-map-file=' + str(modulemap)]
            result['objects'][name]['extra'] = {'path': str(extra), 'sha256': sha(extra),
                                               'modulemap': str(modulemap), 'modulemapSHA256': sha(modulemap)}
        run = subprocess.run(command, capture_output=True, text=True)
        (p / ('targeted-' + name + '-compile.log')).write_text(run.stdout + run.stderr)
        result['commands'].append({'command': command, 'exitCode': run.returncode})
        output.write_text(json.dumps(result, indent=2) + '\n')
        run.check_returncode()
    result['binarySHA256'] = {name: sha(p / ('targeted-' + name)) for name in products}
    fixture_root = pathlib.Path('/private/tmp/swiftjli-native-matrix-fixtures')
    result['fixtureSHA256'] = {case + ext: sha(fixture_root / (case + ext)) for case in result['cases'] for ext in ['.jpg', '.raw']}
    result['status'] = 'compiled'
    output.write_text(json.dumps(result, indent=2) + '\n')
if args.compile_only:
    raise SystemExit(0)
assert sha(compiler) == result['compilerSHA256']
assert sha(p / 'targeted.swift') == result['harnessSHA256']
assert all(sha(p / ('targeted-' + name)) == value for name, value in result['binarySHA256'].items())
result['timingStartedUTC'] = now()
with (p / 'targeted-host.jsonl').open('w') as host:
    for trial in range(4):
        for case in result['cases']:
            pair = {}
            for name in (['baseline', 'candidate'] if trial % 2 == 0 else ['candidate', 'baseline']):
                snapshot = {'utc': now(), 'round': trial + 1, 'case': case, 'label': name,
                            'loadAverage': os.getloadavg(),
                            'processes': subprocess.check_output(['ps', '-axo', 'pid,pcpu,comm'], text=True)}
                host.write(json.dumps(snapshot) + '\n'); host.flush()
                command = [str(p / ('targeted-' + name)), 'benchmark', '/private/tmp/swiftjli-native-matrix-fixtures', case]
                run = subprocess.run(command, capture_output=True, text=True)
                receipt = {'round': trial + 1, 'label': name, 'command': command, 'exitCode': run.returncode,
                           'stderr': run.stderr, 'utc': now()}
                if run.returncode != 0:
                    receipt['stdout'] = run.stdout
                    result['records'].append(receipt)
                    output.write_text(json.dumps(result, indent=2) + '\n')
                    run.check_returncode()
                value = json.loads(run.stdout)
                receipt.update(value); result['records'].append(receipt); pair[name] = value
                output.write_text(json.dumps(result, indent=2) + '\n')
                assert value['pixelExact'] and len(value['samplesSeconds']) == 20
            print(trial + 1, case, round(100 * (pair['candidate']['medianSeconds'] / pair['baseline']['medianSeconds'] - 1), 2), flush=True)
result['status'] = 'complete'; result['finishedUTC'] = now()
result['objectsUnchanged'] = all(sha(value['path']) == value['sha256'] and
    ('extra' not in value or sha(value['extra']['path']) == value['extra']['sha256']) for value in result['objects'].values())
result['compilerUnchanged'] = sha(compiler) == result['compilerSHA256']
output.write_text(json.dumps(result, indent=2) + '\n')
