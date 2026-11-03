"""Diagnostic input-size race simulation; never used for performance timing."""
import json, os, pathlib, subprocess
root = pathlib.Path(__file__).parent
fixture = pathlib.Path('/private/tmp/swiftjli-native-matrix-fixtures/flat-512.jpg')
compiler = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang'
sdk = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
command = [compiler, '-isysroot', sdk, '-dynamiclib', str(root/'input-size-hint.c'), '-o', str(root/'input-size-hint.dylib')]
subprocess.run(command, check=True)
cmd = [str(root/'candidate/swiftjli-cli'), 'decode', '-i', str(fixture), '-o', '-', '--output-format', 'pnm']
reference = subprocess.check_output(cmd)
records = []
for size in [0, fixture.stat().st_size - 1, fixture.stat().st_size, fixture.stat().st_size + 1]:
    env = dict(os.environ, DYLD_INSERT_LIBRARIES=str(root/'input-size-hint.dylib'), SWIFTJLI_SIZE_HINT_PATH=str(fixture), SWIFTJLI_SIZE_HINT_BYTES=str(size))
    completed = subprocess.run(cmd, env=env, capture_output=True)
    assert completed.returncode == 0 and completed.stdout == reference and not completed.stderr
    records.append({'hint':size, 'actual':fixture.stat().st_size, 'outputMatches':True, 'exitCode':completed.returncode})
size = fixture.stat().st_size - 1
env = dict(os.environ, DYLD_INSERT_LIBRARIES=str(root/'input-size-hint.dylib'), SWIFTJLI_SIZE_HINT_PATH=str(fixture), SWIFTJLI_SIZE_HINT_BYTES=str(size))
completed = subprocess.run(cmd + ['--max-memory', str(size)], env=env, capture_output=True)
assert completed.returncode == 5 and b'Input stream exceeds' in completed.stderr and not completed.stdout
records.append({'hint':size, 'maximumMemory':size, 'actual':fixture.stat().st_size, 'exitCode':completed.returncode, 'stderr':completed.stderr.decode(), 'outputBytes':len(completed.stdout)})
(root/'input-size-hint-results.json').write_text(json.dumps(records, indent=2) + '\n')
(root/'input-size-hint-command.json').write_text(json.dumps(command, indent=2) + '\n')
print('Size hint checks:', len(records), 'passed')
