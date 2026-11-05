#!/usr/bin/env python3
"""Large independent DCT oracle, fixed tolerances; execute only in an assigned CPU slot."""
import argparse, array, datetime, hashlib, json, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent
TURBO = pathlib.Path('/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin')
PIN = '6e763ec2099e162bae52a40109ff74269ea9899f'
sha = lambda p: hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()

def pnm(path):
    data = path.read_bytes(); cursor = 0; tokens = []
    for _ in range(4):
        while cursor < len(data):
            if data[cursor] in b' \t\r\n\v\f': cursor += 1
            elif data[cursor] == 35:
                end = data.find(b'\n', cursor)
                if end < 0: raise ValueError('Unterminated PNM comment')
                cursor = end + 1
            else: break
        start = cursor
        while cursor < len(data) and data[cursor] not in b' \t\r\n\v\f': cursor += 1
        if cursor == start: raise ValueError('Missing PNM token')
        tokens.append(data[start:cursor])
    if cursor >= len(data) or data[cursor] not in b' \t\r\n\v\f': raise ValueError('Missing PNM separator')
    cursor += 2 if data[cursor:cursor+2] == b'\r\n' else 1
    magic, width, height, maximum = tokens[0], int(tokens[1]), int(tokens[2]), int(tokens[3])
    if magic != b'P5' or (width, height) != (513, 257) or maximum not in (255, 4095):
        raise ValueError('Unexpected large greyscale PNM descriptor')
    bps = 1 if maximum == 255 else 2; payload = data[cursor:]
    if len(payload) != width * height * bps: raise ValueError('Unexpected PNM payload length')
    if bps == 1: samples = payload
    else:
        samples = array.array('H', payload)
        if sys.byteorder == 'little': samples.byteswap()
    if any(value > maximum for value in samples): raise ValueError('PNM sample exceeds declared precision')
    return (magic.decode(), width, height, maximum), samples

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--build-dir', type=pathlib.Path, default=ROOT / 'build')
    parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'run1')
    args = parser.parse_args()
    if not args.execute:
        print(json.dumps({'status': 'NOT EXECUTED', 'sourceRevision': PIN,
                          'profiles': 8, 'directionComparisons': 16, 'size': [513, 257],
                          'precisions': [8, 12], 'restartMCUs': [3, 1023],
                          'policies': ['scalarCPU', 'automatic'], 'maximumSampleDifferences': {'8': 2, '12': 4}}, indent=2))
        return
    manifest = json.loads((ROOT / 'source-manifest.json').read_text())
    assert manifest['executionStatus'] == 'ready', manifest.get('holdReason', 'Oracle execution is held')
    assert manifest['sourceRevision'] == PIN
    assert not manifest.get('pendingInputs'), 'Release product/build evidence binding is incomplete'
    assert manifest.get('qualificationReceipt'), 'Release qualification receipt is required'
    for item in manifest['files'] + manifest['frozenInputs']:
        path = pathlib.Path(item['path'])
        if not path.is_absolute(): path = ROOT / path
        assert sha(path) == item['sha256'], str(path)
    build = json.loads((args.build_dir / 'build.json').read_text())
    assert build['status'] == 'passed' and build['sourceRevision'] == PIN
    assert build['sourceManifestSHA256'] == sha(ROOT / 'source-manifest.json')
    binary = pathlib.Path(build['binary'])
    assert sha(binary) == build['binarySHA256']
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=False)
    receipt = {'sourceRevision': PIN, 'status': 'running', 'startedUTC': now(),
               'method': '513x257 greyscale DCT; 8/12-bit, restart3/1023 MCUs, scalar/automatic; both codec directions. Compare Swift/djpeg decoders on each identical JPEG stream, never lossy output against the original source. Fixed tolerances2/4; no timing.',
               'sourceManifestSHA256': sha(ROOT / 'source-manifest.json'), 'buildReceiptSHA256': sha(args.build_dir / 'build.json'),
               'binarySHA256': sha(binary), 'cjpegSHA256': sha(TURBO / 'cjpeg'), 'djpegSHA256': sha(TURBO / 'djpeg'),
               'commands': [], 'comparisons': [], 'profiles': [], 'artifacts': []}
    def save(): (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    def run(command):
        index = len(receipt['commands']); label = f'command-{index:03d}'
        row = {'command': list(map(str, command)), 'startedUTC': now(), 'status': 'running'}
        receipt['commands'].append(row); save()
        try:
            result = subprocess.run(command, capture_output=True, timeout=120)
            (output / (label + '.stdout.log')).write_bytes(result.stdout)
            (output / (label + '.stderr.log')).write_bytes(result.stderr)
            row.update(status='completed', exitCode=result.returncode, finishedUTC=now(),
                       stdout=label + '.stdout.log', stderr=label + '.stderr.log')
            save(); result.check_returncode(); return result
        except (subprocess.TimeoutExpired, OSError) as error:
            row.update(status='timeout' if isinstance(error, subprocess.TimeoutExpired) else 'launch-failed',
                       error=repr(error), finishedUTC=now())
            if isinstance(error, subprocess.TimeoutExpired):
                (output / (label + '.stdout.log')).write_bytes(error.stdout or b'')
                (output / (label + '.stderr.log')).write_bytes(error.stderr or b'')
            save(); raise
    try:
        for tool in ['cjpeg', 'djpeg']:
            version = run([TURBO / tool, '-version'])
            assert b'3.2.1' in version.stdout + version.stderr
        for restart in [3, 1023]:
            run([binary, 'generate-dct', output, str(restart)])
            stems = []
            for bits in [8, 12]:
                for policy in ['scalar', 'auto']:
                    stem = f'dct-{bits}-1-0-{policy}-aq0-r{restart}'; stems.append((stem, bits, policy))
                    source = output / f'{stem}-source.pnm'
                    descriptor, _ = pnm(source)
                    assert descriptor == ('P5', 513, 257, (1 << bits) - 1)
                    run([TURBO / 'cjpeg', '-precision', str(bits), '-quality', '85', '-sample', '1x1',
                         '-restart', str(restart) + 'B', '-outfile', output / f'{stem}-oracle.jpg', source])
                    for origin in ['swift', 'oracle']:
                        run([TURBO / 'djpeg', '-strict', '-dct', 'int', '-pnm', '-outfile',
                             output / f'{stem}-djpeg-{origin}.pnm', output / f'{stem}-{origin}.jpg'])
            run([binary, 'verify-dct', output, str(restart)])
            for stem, bits, policy in stems:
                for actual, reference, direction in [('swift-self', 'djpeg-swift', 'Swift encode -> djpeg'),
                                                       ('swift-oracle', 'djpeg-oracle', 'cjpeg encode -> Swift')]:
                    first, samples = pnm(output / f'{stem}-{actual}.pnm')
                    second, expected = pnm(output / f'{stem}-{reference}.pnm')
                    assert first == second == ('P5', 513, 257, (1 << bits) - 1)
                    differences = [abs(a - b) for a, b in zip(samples, expected)]
                    tolerance = 2 if bits == 8 else 4
                    comparison = {'stem': stem, 'direction': direction, 'bits': bits, 'policy': policy,
                                  'restartMCUs': restart, 'samples': len(samples), 'tolerance': tolerance,
                                  'maximumAbsoluteDifference': max(differences),
                                  'differingSamples': sum(value != 0 for value in differences),
                                  'meanAbsoluteDifference': sum(differences) / len(differences),
                                  'actualSHA256': sha(output / f'{stem}-{actual}.pnm'),
                                  'referenceSHA256': sha(output / f'{stem}-{reference}.pnm'),
                                  'passed': max(differences) <= tolerance}
                    receipt['comparisons'].append(comparison); save()
                    assert comparison['passed'], comparison
                receipt['profiles'].append({'stem': stem, 'bits': bits, 'policy': policy, 'restartMCUs': restart}); save()
        assert len(receipt['profiles']) == 8 and len(receipt['comparisons']) == 16
        assert sha(binary) == receipt['binarySHA256']
        assert sha(TURBO / 'cjpeg') == receipt['cjpegSHA256'] and sha(TURBO / 'djpeg') == receipt['djpegSHA256']
        for item in manifest['files'] + manifest['frozenInputs']:
            path = pathlib.Path(item['path'])
            if not path.is_absolute(): path = ROOT / path
            assert sha(path) == item['sha256'], str(path)
        for path in sorted(output.iterdir()):
            if path.suffix in ['.pnm', '.jpg']:
                receipt['artifacts'].append({'path': path.name, 'bytes': path.stat().st_size, 'sha256': sha(path),
                                             'archive': 'generated fixture/output; preserve hash, omit binary payload'})
        receipt.update(status='passed', finishedUTC=now(), identitiesUnchanged=True); save()
        print('Eight large DCT profiles passed both directions at fixed tolerances2/4.')
    except Exception as error:
        receipt.update(status='failed', failure=repr(error), finishedUTC=now()); save(); raise

if __name__ == '__main__': main()
