#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Public DCT oracle: 8/12-bit greyscale and 4:4:4 RGB, sequential/progressive."""
import argparse
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output-dir', type=Path, required=True)
parser.add_argument('--scratch-path', type=Path, required=True)
parser.add_argument('--cjpeg', default=shutil.which('cjpeg'))
parser.add_argument('--djpeg', default=shutil.which('djpeg'))
args = parser.parse_args()
if not args.cjpeg or not args.djpeg:
    parser.error('cjpeg and djpeg are required')
root = args.output_dir.resolve()
root.mkdir(parents=True, exist_ok=True)
repo = Path(__file__).resolve().parent.parent
command = ['swift', 'run', '--package-path', str(repo / 'Examples/LosslessInterop'),
           '--scratch-path', str(args.scratch_path.resolve()), '--disable-sandbox', 'Oracle']
subprocess.run([args.cjpeg, '-version'], check=True)
subprocess.run(command + ['generate-dct', str(root)], check=True)

def pnm(path):
    magic, dimensions, maximum, pixels = path.read_bytes().split(b'\n', 3)
    if magic not in [b'P5', b'P6']:
        raise ValueError('Unexpected PNM format')
    width, height = map(int, dimensions.split())
    stride = 1 if int(maximum) < 256 else 2
    channels = 1 if magic == b'P5' else 3
    if len(pixels) != width * height * channels * stride:
        raise ValueError('Unexpected PNM size')
    samples = list(pixels) if stride == 1 else [int.from_bytes(pixels[i:i+2], 'big') for i in range(0, len(pixels), 2)]
    return (magic, width, height, int(maximum)), samples

stems = []
for bits in [8, 12]:
    for channels in [1, 3]:
        for script in range(3):
            for backend in ['scalar', 'auto']:
                for adaptive in ([0, 1, 2] if bits == 8 else [0]):
                    stem = f'dct-{bits}-{channels}-{script}-{backend}-aq{adaptive}'
                    stems.append(stem)
                    options = ['-progressive'] if script else []
                    subprocess.run([args.cjpeg, '-precision', str(bits), '-quality', '85', '-sample', '1x1',
                                    '-restart', '3B', *options, '-outfile', str(root / f'{stem}-oracle.jpg'),
                                    str(root / f'{stem}-source.pnm')], check=True)
                    for origin in ['swift', 'oracle']:
                        subprocess.run([args.djpeg, '-strict', '-dct', 'int', '-pnm', '-outfile',
                                        str(root / f'{stem}-djpeg-{origin}.pnm'), str(root / f'{stem}-{origin}.jpg')], check=True)
subprocess.run(command + ['verify-dct', str(root)], check=True)
maximum_difference = 0
for stem in stems:
    for ours, reference in [('swift-self', 'djpeg-swift'), ('swift-oracle', 'djpeg-oracle')]:
        a, x = pnm(root / f'{stem}-{ours}.pnm')
        b, y = pnm(root / f'{stem}-{reference}.pnm')
        if a != b:
            raise ValueError(f'Description differs: {stem}')
        difference = max(abs(i-j) for i, j in zip(x, y))
        # Different conforming Float/integer IDCT rounding can differ slightly.
        # Four source sample units is below 0.1% of 12-bit full scale.
        tolerance = 2 if a[3] == 255 else 4
        if difference > tolerance:
            raise ValueError(f'{stem}/{ours}: sample difference {difference} exceeds {tolerance}')
        maximum_difference = max(maximum_difference, difference)
print(f'48 DCT profiles passed both oracle directions; maximum sample difference {maximum_difference}')
