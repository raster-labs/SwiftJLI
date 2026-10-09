#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independently decode the completed cross-codec harness outputs (development only)."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path


def pgm(path):
    data = path.read_bytes()
    # Consume comments/whitespace only while parsing header tokens. Pixel bytes
    # may themselves be whitespace and must never be stripped.
    pattern = rb'(?:\s|\#[^\n]*\n)*'
    match = re.match(rb'P5' + pattern + rb'(\d+)' + pattern + rb'(\d+)' + pattern + rb'(\d+)[\r]?\n', data)
    if not match:
        raise ValueError(f'Unsupported PGM header: {path}')
    width, height, maximum = map(int, match.groups())
    pixels = data[match.end():]
    step = 2 if maximum > 255 else 1
    assert len(pixels) == width * height * step, 'Unexpected PGM payload length'
    return width, height, maximum, [int.from_bytes(pixels[p:p+step], 'big') for p in range(0, len(pixels), step)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    tools = {name: shutil.which(name) for name in ('djpeg', 'opj_decompress')}
    if not all(tools.values()):
        parser.error('Install lossless-capable libjpeg-turbo djpeg and OpenJPEG opj_decompress')
    records = []
    for bits in (12, 16):
        for width, height in ((19, 13), (65, 31), (257, 17)):
            maximum = (1 << bits) - 1
            expected = [0 if x == 0 and y == 0 else maximum if x == 1 and y == 0
                        else (x*193 + y*357 + x*y*17) & maximum
                        for y in range(height) for x in range(width)]
            name = f'{width}x{height}-u{bits}'
            for extension in ('jpg', 'j2k'):
                source = args.input / (name + '.' + extension)
                decoded = args.output / (name + '-' + extension + '.pgm')
                command = ([tools['djpeg'], '-pnm', '-outfile', str(decoded), str(source)] if extension == 'jpg'
                           else [tools['opj_decompress'], '-i', str(source), '-o', str(decoded)])
                result = subprocess.run(command, capture_output=True, text=True, timeout=30)
                record = dict(command=command, exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr,
                              input_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
                records.append(record)
                (args.output / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
                assert result.returncode == 0, record
                w, h, m, samples = pgm(decoded)
                assert (w, h, m) == (width, height, maximum), 'Independent interpretation mismatch'
                assert samples == expected, 'Independent sample mismatch'
                record.update(samples=len(samples), exact=True, output_sha256=hashlib.sha256(decoded.read_bytes()).hexdigest())
    (args.output / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
    print(f'PASS: {len(records)} independent decodes, all samples exact')


if __name__ == '__main__':
    main()
