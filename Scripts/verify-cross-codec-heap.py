#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check Linux cross-codec allocation logs against deliberate-copy controls."""
import argparse
import json
from pathlib import Path


def records(path):
    values = [json.loads(line) for line in path.read_text().splitlines() if line.startswith('{')]
    calibration = [v for v in values if v['event'] == 'calibration']
    assert len(calibration) == 1, 'Missing/duplicate calibration'
    rows = [v for v in values if v['event'] == 'heap']
    expected = {(f'{w}x{h}-u{b}', d) for w, h in [(19, 13), (65, 31), (257, 17)]
                for b in [12, 16] for d in ['J2K-to-JPEG', 'JPEG-to-J2K']}
    assert len(rows) == len(expected) and {(r['case'], r['direction']) for r in rows} == expected
    return calibration[0]['arrayHeaderBytes'], {(r['case'], r['direction']): r for r in rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--control', type=Path, required=True)
    args = parser.parse_args()
    header, baseline = records(args.baseline)
    control_header, control = records(args.control)
    assert header == control_header and 0 <= header <= 256, 'Calibration changed'
    for key, normal in baseline.items():
        copied = control[key]
        assert not normal['controlCopy'] and copied['controlCopy']
        assert normal['destinationCapacity'] == copied['destinationCapacity']
        size = normal['destinationCapacity'] + header
        count = lambda row: sum(b['count'] for b in row['allocationSizes'] if b['requestedBytes'] == size)
        assert count(normal) == 1, f'{key}: expected one final destination allocation'
        assert count(copied) == 2, f'{key}: deliberate copy was not independently detected'
    print(f'PASS: {len(baseline)} single-destination measurements and {len(control)} deliberate-copy controls')


if __name__ == '__main__':
    main()
