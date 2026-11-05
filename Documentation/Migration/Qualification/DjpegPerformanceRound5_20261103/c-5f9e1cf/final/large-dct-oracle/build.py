#!/usr/bin/env python3
"""Build only with --execute and an assigned CPU slot; preserve every attempt."""
import argparse, datetime, hashlib, json, os, pathlib, subprocess

ROOT = pathlib.Path(__file__).resolve().parent
PRODUCTS = pathlib.Path('/private/tmp/swiftjli-round5-c-row-qualification-5f9e1cf-release-build/out/Products/Release')
COMPILER = pathlib.Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
SDK = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
PIN = '5f9e1cf50db4eee4d5439f80602f3dfe9f24b0cd'
sha = lambda p: hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'build')
    args = parser.parse_args()
    output = args.output.resolve()
    modulemap = PRODUCTS.parent.parent / 'Intermediates.noindex/GeneratedModuleMaps/SwiftJLIEntropyC.modulemap'
    command = [str(COMPILER), '-O', '-parse-as-library', '-swift-version', '6',
               '-strict-concurrency=complete', '-target', 'arm64-apple-macos26.0',
               '-sdk', SDK, '-I', str(PRODUCTS), '-Xcc', '-fmodule-map-file=' + str(modulemap),
               str(PRODUCTS / 'SwiftJLI.o'), str(PRODUCTS / 'SwiftJLIEntropyC.o'),
               '-framework', 'Accelerate', str(ROOT / 'DCTOracle.swift'), str(ROOT / 'Main.swift'),
               '-o', str(output / 'large-dct-oracle')]
    if not args.execute:
        print(json.dumps({'status': 'NOT EXECUTED', 'sourceRevision': PIN, 'command': command}, indent=2))
        return
    manifest = json.loads((ROOT / 'source-manifest.json').read_text())
    assert manifest['sourceRevision'] == PIN
    for item in manifest['files'] + manifest['frozenInputs']:
        path = pathlib.Path(item['path'])
        if not path.is_absolute(): path = ROOT / path
        assert sha(path) == item['sha256'], str(path)
    output.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    env['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
    receipt = {'sourceRevision': PIN, 'status': 'running', 'startedUTC': now(),
               'sourceManifestSHA256': sha(ROOT / 'source-manifest.json'),
               'compiler': str(COMPILER), 'compilerSHA256': sha(COMPILER),
               'frozenInputs': manifest['frozenInputs'], 'commands': []}
    def save(): (output / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    def run(cmd, label):
        row = {'command': cmd, 'startedUTC': now(), 'status': 'running'}
        receipt['commands'].append(row); save()
        try:
            result = subprocess.run(cmd, env=env, capture_output=True, timeout=180)
            (output / (label + '.stdout.log')).write_bytes(result.stdout)
            (output / (label + '.stderr.log')).write_bytes(result.stderr)
            row.update(status='completed', exitCode=result.returncode, finishedUTC=now(),
                       stdout=label + '.stdout.log', stderr=label + '.stderr.log')
            save(); result.check_returncode()
        except (subprocess.TimeoutExpired, OSError) as error:
            row.update(status='timeout' if isinstance(error, subprocess.TimeoutExpired) else 'launch-failed',
                       error=repr(error), finishedUTC=now())
            if isinstance(error, subprocess.TimeoutExpired):
                (output / (label + '.stdout.log')).write_bytes(error.stdout or b'')
                (output / (label + '.stderr.log')).write_bytes(error.stderr or b'')
            save(); raise
    try:
        run([str(COMPILER), '--version'], 'compiler-version')
        run(command, 'compile')
        assert sha(COMPILER) == receipt['compilerSHA256']
        for item in manifest['files'] + manifest['frozenInputs']:
            path = pathlib.Path(item['path'])
            if not path.is_absolute(): path = ROOT / path
            assert sha(path) == item['sha256'], str(path)
        receipt.update(status='passed', finishedUTC=now(), binary=str(output / 'large-dct-oracle'),
                       binarySHA256=sha(output / 'large-dct-oracle'), inputsUnchanged=True)
        save()
    except Exception as error:
        receipt.update(status='failed', failure=repr(error), finishedUTC=now()); save(); raise

if __name__ == '__main__': main()
