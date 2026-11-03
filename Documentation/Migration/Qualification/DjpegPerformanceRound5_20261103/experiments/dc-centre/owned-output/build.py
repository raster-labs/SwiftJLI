import argparse
import hashlib
import json
import pathlib
import subprocess

root = pathlib.Path(__file__).parent
parser = argparse.ArgumentParser()
parser.add_argument('--products', type=pathlib.Path, default=pathlib.Path('/private/tmp/swiftjli-round4-build/out/Products/Release'))
parser.add_argument('--source-revision', default='bbb0b1a9a602807643fc254fb4e0d54a162d5ae8 (production identical to0a8acd7)')
args = parser.parse_args()
toolchain = pathlib.Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin')
sdk = pathlib.Path('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk')
turbo = pathlib.Path('/opt/homebrew/Cellar/jpeg-turbo/3.2.1')
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
commands = [
    [str(toolchain / 'clang'), '-O3', '-std=c11', '-Wall', '-Wextra', '-Werror', '-target', 'arm64-apple-macos26.0',
     '-isysroot', str(sdk), '-I', str(turbo / 'include'), '-c', str(root / 'jpeg_bench.c'), '-o', str(root / 'jpeg_bench.o')],
    [str(toolchain / 'swiftc'), '-O', '-parse-as-library', '-swift-version', '6', '-strict-concurrency=complete',
     '-target', 'arm64-apple-macos26.0', '-sdk', str(sdk), '-I', str(args.products), '-I', str(root),
     str(args.products / 'SwiftJLI.o'), str(root / 'jpeg_bench.o'), str(turbo / 'lib/libjpeg.a'),
     '-framework', 'Accelerate', str(root / 'Compare.swift'), '-o', str(root / 'compare')],
]
result = {'sourceRevision': args.source_revision, 'commands': [],
          'sourceSHA256': {p.name: sha(p) for p in [root / n for n in ['Compare.swift', 'jpeg_bench.c', 'jpeg_bench.h', 'module.modulemap', 'build.py', 'run.py']]},
          'SwiftJLIObjectSHA256': sha(args.products / 'SwiftJLI.o'),
          'libjpegArchive': str(turbo / 'lib/libjpeg.a'), 'libjpegArchiveSHA256': sha(turbo / 'lib/libjpeg.a'),
          'jpeglibHeaderSHA256': sha(turbo / 'include/jpeglib.h'),
          'compilerSHA256': sha(toolchain / 'swiftc'),
          'compilerVersion': subprocess.check_output([str(toolchain / 'swiftc'), '--version'], text=True, stderr=subprocess.STDOUT)}
for index, command in enumerate(commands):
    with (root / f'build-{index}.log').open('w') as log:
        completed = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    result['commands'].append({'command': command, 'exitCode': completed.returncode, 'log': f'build-{index}.log'})
    (root / 'build.json').write_text(json.dumps(result, indent=2) + '\n')
    if completed.returncode:
        raise SystemExit(completed.returncode)
result['binarySHA256'] = sha(root / 'compare')
result['loadedLibraries'] = subprocess.check_output(['otool', '-L', str(root / 'compare')], text=True)
(root / 'build.json').write_text(json.dumps(result, indent=2) + '\n')
print('Built one executable containing both decoders; libjpeg3.2.1 archive pinned statically.')
