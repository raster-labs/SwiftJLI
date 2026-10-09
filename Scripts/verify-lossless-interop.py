#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independent SOF3 oracle: requires Swift and lossless-capable libjpeg-turbo tools."""
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
    parser.error('cjpeg and djpeg must be installed or supplied explicitly')
root = args.output_dir.resolve()
root.mkdir(parents=True, exist_ok=True)
repo = Path(__file__).resolve().parent.parent
command = ['swift', 'run', '--package-path', str(repo / 'Examples/LosslessInterop'),
           '--scratch-path', str(args.scratch_path.resolve()), '--disable-sandbox', 'Oracle']
subprocess.run([args.cjpeg, '-version'], check=True)
subprocess.run(command + ['generate', str(root)], check=True)

def pgm(path):
    header = path.read_bytes().split(b'\n', 3)
    if len(header) != 4 or header[0] != b'P5':
        raise ValueError('Unexpected oracle PGM header')
    width, height = map(int, header[1].split())
    maximum, pixels = int(header[2]), header[3]
    stride = 1 if maximum < 256 else 2
    if len(pixels) != width * height * stride:
        raise ValueError('Unexpected oracle PGM size')
    samples = list(pixels) if stride == 1 else [int.from_bytes(pixels[i:i+2], 'big') for i in range(0, len(pixels), 2)]
    return width, height, samples

for bits in range(2, 17):
    for predictor in range(1, 8):
        for point in [0, min(2, bits - 1)]:
            stem = f'{bits}-{predictor}-pt{point}'
            source = root / f'{stem}.pgm'
            subprocess.run([args.cjpeg, '-precision', str(bits), '-lossless', f'{predictor},{point}',
                            '-restart', '2', '-outfile', str(root / f'{stem}-oracle.jpg'), str(source)], check=True)
            decoded = root / f'{stem}-djpeg.pgm'
            subprocess.run([args.djpeg, '-strict', '-pnm', '-outfile', str(decoded),
                            str(root / f'{stem}-swift.jpg')], check=True)
            w, h, original = pgm(source)
            expected = (w, h, [(value >> point) << point for value in original])
            if expected != pgm(decoded):
                raise ValueError(f'Independent decode differs for precision/predictor {stem}')
print('210 SwiftJLI outputs matched the declared point transform through libjpeg-turbo', flush=True)
subprocess.run(command + ['verify', str(root)], check=True)
