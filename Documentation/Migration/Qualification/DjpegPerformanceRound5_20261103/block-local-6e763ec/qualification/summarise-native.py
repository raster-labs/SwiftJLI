#!/usr/bin/env python3
"""Recompute paired medians and the declared repeated-five-percent screen."""
import argparse
import json
from pathlib import Path
import statistics

parser = argparse.ArgumentParser()
parser.add_argument('kind', choices=['lossless', 'dct'])
args = parser.parse_args()
root = Path(__file__).resolve().parent / ('native-' + args.kind + '-1')
data = json.loads((root / 'receipt.json').read_text())
pairs = {}
if args.kind == 'lossless':
    records = [dict(record, round=batch['round'], label=batch['binary'])
               for batch in data['matrix'] for record in batch['records']]
else:
    records = data['records']
for record in records:
    assert len(record['samplesSeconds']) == 20
    assert statistics.median(record['samplesSeconds']) == record['medianSeconds']
    name = record['case'] if args.kind == 'lossless' else record['fixture']
    pairs.setdefault(name, {}).setdefault(record['round'], {})[record['label']] = record
rows = []
for name, rounds in pairs.items():
    assert sorted(rounds) == [1, 2]
    assert all(set(pair) == {'baseline', 'candidate'} for pair in rounds.values())
    changes = [(rounds[n]['candidate']['medianSeconds'] / rounds[n]['baseline']['medianSeconds'] - 1) * 100
               for n in [1, 2]]
    rows.append({'case': name, 'roundPercentChange': changes,
                 'repeatedOver5PercentRegression': all(change > 5 for change in changes),
                 'baselineMilliseconds': [rounds[n]['baseline']['medianSeconds'] * 1000 for n in [1, 2]],
                 'candidateMilliseconds': [rounds[n]['candidate']['medianSeconds'] * 1000 for n in [1, 2]]})
if args.kind == 'lossless':
    exact = all(record['pixelExact'] for record in records)
else:
    exact = all(pair['candidate']['outputSHA256'] == pair['baseline']['outputSHA256'] and
                pair['candidate']['outputBytes'] == pair['baseline']['outputBytes']
                for rounds in pairs.values() for pair in rounds.values())
summary = {'sourceRevision': data['candidateRevision'], 'baselineRevision': data['baselineRevision'],
           'status': data['status'], 'cases': len(rows), 'pairs': len(rows) * 2,
           'allOutputExact': exact, 'identityChecks': {key: value for key, value in data.items() if key.endswith('Unchanged')},
           'repeatedOver5PercentRegressions': [row['case'] for row in rows if row['repeatedOver5PercentRegression']],
           'rows': rows}
if args.kind == 'lossless':
    summary['thermalStates'] = sorted(set(record['thermalState'] for record in records))
assert len(rows) == (16 if args.kind == 'lossless' else 18)
assert exact and data['status'] == 'complete' and all(summary['identityChecks'].values())
out = root / 'summary.json'
assert not out.exists(), 'Refusing to overwrite a retained summary'
out.write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
