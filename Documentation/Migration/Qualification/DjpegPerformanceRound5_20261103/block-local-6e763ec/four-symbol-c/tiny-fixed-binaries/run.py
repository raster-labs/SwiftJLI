#!/usr/bin/env python3
"""One predeclared diagnostic; retains the original failed acceptance gate."""
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
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
if out.exists():
    raise SystemExit('Refusing to overwrite or repeat this diagnostic')
expected = {plan['originalReceipt']: plan['originalReceiptSHA256'],
            plan['harnessPath']: plan['harnessSHA256'],
            str(plan_path): sha(plan_path), str(Path(__file__)): sha(__file__)}
expected.update({item['path']: item['sha256'] for item in plan['binaries'].values()})
expected.update({item['path']: item['sha256'] for item in plan['fixtures'].values()})
assert all(sha(path) == digest for path, digest in expected.items()), 'Changed pinned input'
out.mkdir()
receipt = {'status': 'running', 'startedUTC': now(), 'planSHA256': sha(plan_path),
           'pinnedInputs': expected, 'records': [], 'hostLoadBefore': os.getloadavg(),
           'originalAcceptanceGate': 'failed-and-preserved'}

def save():
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

save()
try:
    for scheduled in plan['schedule']:
        for name in scheduled['caseOrder']:
            fixture = plan['fixtures'][name]
            for label in scheduled['binaryOrder']:
                log = out / ('round' + str(scheduled['round']) + '-' + Path(name).stem + '-' + label)
                command = [plan['binaries'][label]['path'], fixture['path']]
                entry = {'round': scheduled['round'], 'case': name, 'label': label,
                         'binaryOrder': scheduled['binaryOrder'], 'command': command,
                         'hostLoadBefore': os.getloadavg(), 'startedUTC': now()}
                with log.with_suffix('.stdout.json').open('x') as stdout, log.with_suffix('.stderr.log').open('x') as stderr:
                    result = subprocess.run(command, stdout=stdout, stderr=stderr)
                entry.update(exitCode=result.returncode, finishedUTC=now())
                receipt['records'].append(entry)
                save()
                assert result.returncode == 0, 'Decoder process failed; raw output retained'
                data = json.loads(log.with_suffix('.stdout.json').read_text())
                entry['result'] = data
                save()
                assert data['fixture'] == name
                assert len(data['samplesSeconds']) == plan['measuredSamplesPerProcess']
                assert statistics.median(data['samplesSeconds']) == data['medianSeconds']
                assert data['outputSHA256'] == fixture['expectedOutputSHA256']
                assert data['outputBytes'] == fixture['expectedOutputBytes']
        print('Completed fixed-binary tiny round', scheduled['round'], flush=True)
    assert len(receipt['records']) == plan['expectedRecords']
    rows = []
    for name in plan['fixtures']:
        pairs = []
        for scheduled in plan['schedule']:
            values = {entry['label']: entry['result']['medianSeconds'] for entry in receipt['records']
                      if entry['case'] == name and entry['round'] == scheduled['round']}
            pairs.append({'round': scheduled['round'], 'baselineFirst': scheduled['binaryOrder'][0] == 'baseline',
                          'baselineMicroseconds': values['baseline'] * 1e6,
                          'candidateMicroseconds': values['candidate'] * 1e6,
                          'changeMicroseconds': (values['candidate'] - values['baseline']) * 1e6,
                          'percentChange': (values['candidate'] / values['baseline'] - 1) * 100})
        changes = [pair['percentChange'] for pair in pairs]
        rows.append({'case': name, 'pairs': pairs, 'medianPairedPercentChange': statistics.median(changes),
                     'rangePercentChange': [min(changes), max(changes)],
                     'roundsOver5Percent': sum(change > 5 for change in changes),
                     'orderStrataMedianPercentChange': {label: statistics.median(pair['percentChange'] for pair in pairs
                         if pair['baselineFirst'] == baseline_first)
                         for label, baseline_first in [('baselineFirst', True), ('candidateFirst', False)]}})
    receipt['summary'] = rows
    receipt['status'] = 'complete-diagnostic-only'
except BaseException as error:
    receipt['status'] = 'failed'
    receipt['error'] = repr(error)
    raise
finally:
    receipt['identityChecks'] = {path: sha(path) == digest for path, digest in expected.items()}
    if not all(receipt['identityChecks'].values()):
        receipt['status'] = 'failed-artifact-verification'
    receipt['hostLoadAfter'] = os.getloadavg()
    receipt['finishedUTC'] = now()
    save()
if receipt['status'] != 'complete-diagnostic-only':
    sys.exit(1)
print(json.dumps(receipt['summary'], indent=2))
