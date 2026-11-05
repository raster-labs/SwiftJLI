#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independent raw RGB DCT decoding with libjpeg-turbo, using existing 2/4-unit tolerances."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output-dir', type=Path, required=True)
parser.add_argument('--scratch-path', type=Path, required=True)
args = parser.parse_args()
root = args.output_dir.resolve()
root.mkdir(parents=True, exist_ok=False)
repo = Path(__file__).resolve().parent.parent
tools = {name: shutil.which(name) for name in ['cjpeg', 'djpeg']}
if not all(tools.values()):
    parser.error('libjpeg-turbo cjpeg and djpeg are required')
record = {'status': 'running', 'commands': [], 'results': [], 'tolerances': {'8': 2, '12': 4}}

def run(command):
    result = subprocess.run(command, text=True, capture_output=True)
    record['commands'].append({'argv': command, 'exitCode': result.returncode,
                               'stdout': result.stdout, 'stderr': result.stderr})
    (root / 'results.json').write_text(json.dumps(record, indent=2) + '\n')
    result.check_returncode()


def samples(path):
    magic, dimensions, maximum, pixels = path.read_bytes().split(b'\n', 3)
    bits = 8 if int(maximum) == 255 else 12
    width, height = map(int, dimensions.split())
    step = 1 if bits == 8 else 2
    assert magic == b'P6' and len(pixels) == width * height * 3 * step
    values = [int.from_bytes(pixels[i:i+step], 'big') for i in range(0, len(pixels), step)]
    return (magic, dimensions, maximum), values

try:
    run([tools['cjpeg'], '-version'])
    for bits in [8, 12]:
        maximum = (1 << bits) - 1
        data = bytearray(f'P6\n31 23\n{maximum}\n'.encode())
        for y in range(23):
            for x in range(31 * 3):
                value = (x * 137 + y * 193 + x * y * 7) & maximum
                data.extend(value.to_bytes(1 if bits == 8 else 2, 'big'))
        source = root / f'source-{bits}.pnm'
        source.write_bytes(data)
        for progressive in [False, True]:
            stem = f'rgb-{bits}-' + ('progressive' if progressive else 'sequential')
            run([tools['cjpeg'], '-rgb', '-precision', str(bits), '-quality', '85', '-sample', '1x1',
                 *(['-progressive'] if progressive else []), '-outfile', str(root / (stem + '.jpg')), str(source)])
            run([tools['djpeg'], '-strict', '-dct', 'int', '-pnm', '-outfile', str(root / (stem + '-reference.pnm')),
                 str(root / (stem + '.jpg'))])
    run(['swift', 'run', '--package-path', str(repo / 'Examples/LosslessInterop'), '--scratch-path',
         str(args.scratch_path.resolve()), 'Oracle', 'verify-raw-rgb', str(root)])
    for bits in [8, 12]:
        for mode in ['sequential', 'progressive']:
            stem = f'rgb-{bits}-{mode}'
            description, reference = samples(root / (stem + '-reference.pnm'))
            for backend in ['scalar', 'auto']:
                for storage in ['allocated', 'borrowed']:
                    name = f'{stem}-{backend}-{storage}'
                    actual_description, actual = samples(root / (name + '.pnm'))
                    assert description == actual_description
                    difference = max(abs(a-b) for a,b in zip(actual, reference))
                    assert difference <= record['tolerances'][str(bits)], (name, difference)
                    record['results'].append({'case': name, 'maximumSampleDifference': difference})
    record['status'] = 'passed'
except BaseException as error:
    record['status'] = 'failed'
    record['error'] = repr(error)
    raise
finally:
    record['fixtureSHA256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in root.iterdir() if p.suffix in ['.pnm', '.jpg']}
    (root / 'results.json').write_text(json.dumps(record, indent=2) + '\n')
print(f'{len(record["results"])} independent raw RGB cases passed')
