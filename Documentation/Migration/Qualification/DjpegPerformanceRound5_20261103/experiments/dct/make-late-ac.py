import hashlib, json, pathlib, subprocess
root = pathlib.Path('/private/tmp/swiftjli-round5-dct-fixtures')
root.mkdir(exist_ok=True)
cli = '/private/tmp/swiftjli-round4-build/out/Products/Release/swiftjli-cli'
records = []
for bits in [8, 12]:
    for kind, size in [('late-ac', 512), ('flat', 19), ('noise', 19)]:
        middle = (1 << (bits - 1)) + 1
        maximum = (1 << bits) - 1
        state = 42
        payload = bytearray()
        for y in range(size):
            for x in range(size):
                value = middle
                if kind == 'late-ac' and x == 511 and y in [127, 255, 383, 511]:
                    value = maximum
                if kind == 'noise':
                    state = (1664525 * state + 1013904223) & 0xffffffff
                    value = (state >> 12) & maximum
                payload += value.to_bytes(1 if bits == 8 else 2, 'big')
        name = f'{kind}-{bits}-{size}'
        source = root / (name + '.pgm')
        target = root / (name + '.jpg')
        source.write_bytes(f'P5\n{size} {size}\n{maximum}\n'.encode() + payload)
        command = [cli, 'encode', '-i', str(source), '-o', str(target), '--input-format', 'pgm',
                   '--output-format', 'jpeg', '--mode', 'lossy', '--quality', '90']
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode: raise RuntimeError(result.stderr)
        records.append(dict(command=command, exitCode=result.returncode,
            sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest(),
            fixtureSHA256=hashlib.sha256(target.read_bytes()).hexdigest()))
(root / 'provenance.json').write_text(json.dumps(dict(
    source='In-house deterministic synthetic flat/LCG noise and sparse last-block impulses; no external image material.',
    baseline='bbb0b1a9a602807643fc254fb4e0d54a162d5ae8', records=records),indent=2)+'\n')
print('Created', len(records), 'fixtures')
