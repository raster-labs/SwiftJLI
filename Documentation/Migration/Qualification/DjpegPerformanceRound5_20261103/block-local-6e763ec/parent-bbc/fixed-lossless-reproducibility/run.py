#!/usr/bin/env python3
"""Fixed audit of retained executables; never changes an acceptance decision."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys

root = Path(__file__).resolve().parent
plan_path = root / 'plan.json'
plan = json.loads(plan_path.read_text())
out = root / 'run1'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
if out.exists():
    raise SystemExit('Refusing to repeat or overwrite this diagnostic')
expected = {str(plan_path): sha(plan_path), str(Path(__file__)): sha(__file__)}
for kind, spec in plan['kinds'].items():
    expected.update({spec['originalReceipt']: spec['originalReceiptSHA256'],
                     spec['harnessPath']: spec['harnessSHA256']})
    expected.update({v['path']: v['sha256'] for v in spec['binaries'].values()})
    if kind == 'lossless':
        expected.update(spec['fixtureSHA256'])
    else:
        expected.update({v['path']: v['sha256'] for v in spec['fixtures'].values()})
assert all(sha(p) == h for p, h in expected.items()), 'Changed pinned input'
out.mkdir()
receipt = {'status': 'running', 'startedUTC': now(), 'planSHA256': sha(plan_path),
           'pinnedInputs': expected, 'processes': [], 'records': [],
           'hostLoadBefore': os.getloadavg(), 'originalAcceptanceGate': 'held-and-preserved'}

def save():
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

def run_process(kind, scheduled, label, case=None):
    spec = plan['kinds'][kind]
    command = [spec['binaries'][label]['path']]
    command += ['benchmark', spec['fixtureRoot']] if kind == 'lossless' else [spec['fixtures'][case]['path']]
    stem = 'round' + str(scheduled['round']) + '-' + kind + '-' + (Path(case).stem if case else 'all16') + '-' + label
    stdout_path, stderr_path = out / (stem + '.stdout'), out / (stem + '.stderr')
    entry = {'kind': kind, 'round': scheduled['round'], 'label': label,
             'binaryOrder': scheduled['binaryOrder'], 'command': command,
             'startedUTC': now(), 'hostLoadBefore': os.getloadavg()}
    with stdout_path.open('x') as stdout, stderr_path.open('x') as stderr:
        result = subprocess.run(command, stdout=stdout, stderr=stderr)
    entry.update(exitCode=result.returncode, finishedUTC=now(), stdout=str(stdout_path), stderr=str(stderr_path))
    receipt['processes'].append(entry)
    save()
    assert result.returncode == 0, 'Process failed; raw outputs retained'
    rows = [json.loads(line) for line in stdout_path.read_text().splitlines()] if kind == 'lossless' else [json.loads(stdout_path.read_text())]
    if kind == 'lossless':
        assert len(rows) == 16 and {row['case'] for row in rows} == set(spec['expectedCases'])
    for row in rows:
        receipt['records'].append({'kind': kind, 'round': scheduled['round'], 'label': label,
                                   'binaryOrder': scheduled['binaryOrder'], 'result': row})
    save()
    for row in rows:
        assert len(row['samplesSeconds']) == 20
        assert statistics.median(row['samplesSeconds']) == row['medianSeconds']
        if kind == 'lossless':
            assert row['pixelExact'] and row['checksum'] == spec['expectedCases'][row['case']]
        else:
            fixture = spec['fixtures'][case]
            assert row['fixture'] == case
            assert row['outputSHA256'] == fixture['expectedOutputSHA256']
            assert row['outputBytes'] == fixture['expectedOutputBytes']

def original_records(kind, spec):
    data = json.loads(Path(spec['originalReceipt']).read_text())
    if kind == 'lossless':
        return [{'round': batch['round'], 'label': batch['binary'], 'result': row}
                for batch in data['matrix'] for row in batch['records']]
    return [{'round': row['round'], 'label': row['label'], 'result': row} for row in data['records']]

def summarise(pairs):
    changes = [pair['percentChange'] for pair in pairs]
    return {'medianPairedPercentChange': statistics.median(changes),
            'rangePercentChange': [min(changes), max(changes)],
            'roundsOver5Percent': sum(value > 5 for value in changes),
            'allRoundsOver5Percent': all(value > 5 for value in changes),
            'orderStrataMedianPercentChange': {label: statistics.median(pair['percentChange'] for pair in pairs if pair['baselineFirst'] == flag)
                for label, flag in [('baselineFirst', True), ('candidateFirst', False)]}}

save()
try:
    for scheduled in plan['schedule']:
        for kind in scheduled['kindOrder']:
            if kind == 'lossless':
                for label in scheduled['binaryOrder']:
                    run_process(kind, scheduled, label)
            else:
                for case in scheduled['dctCaseOrder']:
                    for label in scheduled['binaryOrder']:
                        run_process(kind, scheduled, label, case)
        print('Completed fixed reproducibility round', scheduled['round'], flush=True)
    assert len(receipt['processes']) == plan['expectedProcesses']
    assert sum(row['kind'] == 'lossless' for row in receipt['records']) == plan['expectedLosslessRecords']
    assert sum(row['kind'] == 'dct' for row in receipt['records']) == plan['expectedDCTRecords']
    analyses = []
    for kind, spec in plan['kinds'].items():
        original = original_records(kind, spec)
        diagnostic = [row for row in receipt['records'] if row['kind'] == kind]
        for case in spec['selectedCases']:
            pairs = []
            for phase, rows, count in [('original', original, 2), ('diagnostic', diagnostic, 6)]:
                for number in range(1, count + 1):
                    values = {row['label']: row['result']['medianSeconds'] for row in rows if row['round'] == number and
                              row['result'].get('case', row['result'].get('fixture')) == case}
                    assert set(values) == {'baseline', 'candidate'}
                    pairs.append({'phase': phase, 'round': number, 'baselineFirst': number % 2 == 1,
                                  'baselineMicroseconds': values['baseline'] * 1e6,
                                  'candidateMicroseconds': values['candidate'] * 1e6,
                                  'changeMicroseconds': (values['candidate'] - values['baseline']) * 1e6,
                                  'percentChange': (values['candidate'] / values['baseline'] - 1) * 100})
            analyses.append({'kind': kind, 'case': case, 'pairs': pairs,
                             'originalTwo': summarise(pairs[:2]), 'diagnosticSix': summarise(pairs[2:]),
                             'combinedEightDescriptiveOnly': summarise(pairs)})
    receipt['analysis'] = analyses
    receipt['status'] = 'complete-diagnostic-only'
except BaseException as error:
    receipt['status'] = 'failed'
    receipt['error'] = repr(error)
    raise
finally:
    receipt['identityChecks'] = {p: Path(p).is_file() and sha(p) == h for p, h in expected.items()}
    if not all(receipt['identityChecks'].values()):
        receipt['status'] = 'failed-artifact-verification'
    receipt['hostLoadAfter'] = os.getloadavg()
    receipt['finishedUTC'] = now()
    save()
if receipt['status'] != 'complete-diagnostic-only':
    sys.exit(1)
print(json.dumps([{key: value for key, value in row.items() if key != 'pairs'} for row in receipt['analysis']], indent=2))
