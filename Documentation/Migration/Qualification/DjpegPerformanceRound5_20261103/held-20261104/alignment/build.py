from pathlib import Path
import datetime, hashlib, json, shlex, subprocess
from provenance import import_snapshot, unchanged

root = Path(__file__).resolve().parent
out = root / 'build1'
if out.exists(): raise SystemExit('Refusing to overwrite a build receipt')
out.mkdir()
clang = Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang')
swift = clang.with_name('swiftc')
sdk = Path('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.2.sdk')
source = Path('/private/tmp/swiftjli-round5-c-row-entry-alignment')
control = Path('/private/tmp/swiftjli-round5-c-row-composed')
products = {
    'baseline': Path('/private/tmp/swiftjli-round5-5f9e1cf-fma-baseline/out/Products/Release'),
    'candidate': Path('/private/tmp/swiftjli-round5-composed-c-fma256-tiny-build/out/Products/Release'),
}
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
plan = json.loads((root / 'plan.json').read_text())
assert subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip() == plan['alignedSourceRevision']
assert not subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True)
assert subprocess.check_output(['git', '-C', str(control), 'rev-parse', 'HEAD'], text=True).strip() == plan['qualifiedSourceRevision']
assert not subprocess.check_output(['git', '-C', str(control), 'status', '--porcelain'], text=True)
assert all(sha(path) == value for path, value in plan['expectedArtifacts'].items())
pins = {str(path): sha(path) for folder in products.values() for path in [folder / 'SwiftJLI.o', folder / 'SwiftJLIEntropyC.o']}
pins.update({str(p): sha(p) for p in [clang, swift, root / 'Matrix.swift', root / 'build.py', root / 'provenance.py', root / 'plan.json']})
for folder in [source, control]:
    for path in (folder / 'Sources/SwiftJLIEntropyC').rglob('*'):
        if path.is_file(): pins[str(path)] = sha(path)
imports = {label: import_snapshot(folder) for label, folder in products.items()}
receipt = {'status': 'building', 'startedUTC': now(), 'plan': plan, 'pins': pins,
           'imports': imports, 'commands': [], 'products': {}, 'binaries': {}}
def save(): (out / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n')
def run(command, name):
    entry = {'command': [str(v) for v in command], 'startedUTC': now(), 'stdout': name + '.stdout.log', 'stderr': name + '.stderr.log'}
    receipt['commands'].append(entry); save()
    with (out / entry['stdout']).open('w') as stdout, (out / entry['stderr']).open('w') as stderr:
        result = subprocess.run(entry['command'], stdout=stdout, stderr=stderr)
    entry.update(exitCode=result.returncode, finishedUTC=now()); save()
    if result.returncode: raise RuntimeError(name + ' failed')
try:
    run([clang, '--version'], 'clang-version')
    run([swift, '--version'], 'swift-version')
    for label, folder in [('control', control), ('aligned', source)]:
        units = []
        for name in ['ACBlock', 'LosslessCodeZeroRow', 'LosslessRow']:
            obj = out / (label + '-' + name + '.o'); units.append(obj)
            command = [clang, '-target', 'arm64-apple-macos26.0', '-isysroot', sdk, '-Os', '-g',
                '-fmodules', '-gmodules', '-fmodules-cache-path=' + str(out / 'ModuleCache'),
                '-fpascal-strings', '-DSWIFT_PACKAGE', '-DXcode', '-std=c11', '-Wall', '-Wextra', '-Werror',
                '-I', folder / 'Sources/SwiftJLIEntropyC/include', '-c',
                folder / ('Sources/SwiftJLIEntropyC/' + name + '.c'), '-o', obj]
            run(command, label + '-' + name)
        combined = out / (label + '-SwiftJLIEntropyC.o')
        run([clang, '-target', 'arm64-apple-macos26.0', '-isysroot', sdk, '-Os', '-r', '-nostdlib',
             '-Xlinker', '-reproducible', *units, '-o', combined], label + '-link-C')
        receipt['products'][label] = {'path': str(combined), 'sha256': sha(combined)}
    for owner, folder in products.items():
        for mode in ['Original', 'Aligned']:
            label = owner + mode
            cobject = folder / 'SwiftJLIEntropyC.o' if mode == 'Original' else out / 'aligned-SwiftJLIEntropyC.o'
            binary = out / label
            modulemap = folder.parent.parent / 'Intermediates.noindex/GeneratedModuleMaps/SwiftJLIEntropyC.modulemap'
            run([swift, '-O', '-parse-as-library', '-target', 'arm64-apple-macos26.0', '-sdk', sdk,
                 '-I', folder, folder / 'SwiftJLI.o', '-framework', 'Accelerate', root / 'Matrix.swift',
                 '-o', binary, cobject, '-Xcc', '-fmodule-map-file=' + str(modulemap)], 'link-' + label)
            receipt['binaries'][label] = {'path': str(binary), 'sha256': sha(binary),
                'swiftObject': str(folder / 'SwiftJLI.o'), 'cObject': str(cobject), 'cObjectSHA256': sha(cobject)}
    receipt['inputsUnchanged'] = all(sha(path) == value for path, value in pins.items()) and all(unchanged(v) for v in imports.values())
    assert receipt['inputsUnchanged']
    receipt['status'] = 'built; codegen and actual linked alignment gate pending'
except BaseException as error:
    receipt['status'] = 'failed'; receipt['error'] = repr(error); raise
finally:
    receipt['finishedUTC'] = now(); save()
