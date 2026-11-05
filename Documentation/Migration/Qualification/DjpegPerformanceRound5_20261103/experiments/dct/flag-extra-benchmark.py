import hashlib, json, pathlib, subprocess
root = pathlib.Path('/private/tmp/swiftjli-round5-dct-evidence')
fixtureRoot = pathlib.Path('/private/tmp/swiftjli-round5-dct-fixtures')
products = {'baseline': pathlib.Path('/private/tmp/swiftjli-round5-dct-direct-build/out/Products/Release'),
            'candidate': pathlib.Path('/private/tmp/swiftjli-round5-dct-flag-build/out/Products/Release')}
compiler = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
sdk = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
commands = {}
binaries = {}
for label, product in products.items():
    binary = root / ('flag-tiny-' + label)
    command = [compiler, '-O', '-parse-as-library', '-target', 'arm64-apple-macos26.0', '-sdk', sdk,
               '-I', str(product), str(product/'SwiftJLI.o'), '-framework', 'Accelerate',
               str(root/'tiny-native.swift'), '-o', str(binary)]
    subprocess.run(command, check=True)
    commands[label] = command
    binaries[label] = binary
result = dict(compileCommands=commands, baseline='4277947911d357f8c7c364051bcef14e89fc1368',
              timing='Provisional under host contention; tiny samples average500 complete decode/free iterations.',
              records=[])
for trial in range(2):
    for fixture in sorted(fixtureRoot.glob('*.jpg')):
        pair = {}
        for label in (['baseline','candidate'] if trial%2==0 else ['candidate','baseline']):
            binary = binaries[label] if '-19' in fixture.stem else root/('flag-native-'+label)
            row = json.loads(subprocess.check_output([str(binary), str(fixture)],text=True))
            pair[label] = row
            result['records'].append(dict(round=trial+1, label=label,
                fixtureSHA256=hashlib.sha256(fixture.read_bytes()).hexdigest(), **row))
        assert pair['baseline']['outputSHA256'] == pair['candidate']['outputSHA256'], str(fixture)
        print(fixture.name,trial+1,{label:round(row['medianSeconds']*1000,4) for label,row in pair.items()},flush=True)
        (root/'flag-extra-native.json').write_text(json.dumps(result,indent=2)+'\n')
print('All extra outputs match exactly.')
