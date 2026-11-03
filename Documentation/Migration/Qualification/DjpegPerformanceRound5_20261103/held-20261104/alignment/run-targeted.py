from pathlib import Path
import datetime, hashlib, json, os, subprocess
from provenance import unchanged

root = Path(__file__).resolve().parent
out = root / 'targeted-run1'
if out.exists(): raise SystemExit('Refusing to overwrite retained run data')
build = json.loads((root / 'build1/build.json').read_text())
gate = json.loads((root / 'build1/codegen-gate.json').read_text())
assert gate['passed'], 'Codegen and actual linked alignment must pass first'
assert build['status'] == 'built; codegen and actual linked alignment gate pending'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
assert gate['buildReceiptSHA256'] == sha(root / 'build1/build.json'), 'Stale codegen gate'
assert gate['binarySHA256'] == {label: item['sha256'] for label, item in build['binaries'].items()}
fixtures = Path('/private/tmp/swiftjli-native-matrix-fixtures')
cases = ['ramp-512', 'noise-512', 'ramp-2048', 'noise-2048', 'ramp-3072', 'noise-3072']
labels = ['baselineOriginal', 'candidateOriginal', 'baselineAligned', 'candidateAligned']
# Williams design: every label occurs at every position once and every ordered
# adjacent pair occurs once. Reverse case order on alternate process rounds.
orders = [[0, 1, 3, 2], [1, 2, 0, 3], [2, 3, 1, 0], [3, 0, 2, 1]]
pins = dict(build['pins'])
pins.update({str(p): sha(p) for p in [root / 'run-targeted.py', root / 'build1/build.json', root / 'build1/codegen-gate.json']})
for item in build['binaries'].values(): pins[item['path']] = item['sha256']; pins[item['cObject']] = item['cObjectSHA256']
for case in cases:
    for suffix in ['jpg', 'raw']:
        path = fixtures / (case + '.' + suffix); pins[str(path)] = sha(path)
assert all(sha(p) == h for p, h in pins.items()) and all(unchanged(v) for v in build['imports'].values())
out.mkdir()
result = {'status': 'running', 'startedUTC': now(), 'pins': pins, 'cases': cases,
    'orderDesign': [[labels[i] for i in row] for row in orders], 'records': [],
    'method': 'Public allocated-output decoder, unchanged original matrix timer, full source.raw oracle before5 warmups/20 samples per process. Six cases, four balanced process-level comparisons; no pooled per-decode significance claim.'}
def save(): (out / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
save()
try:
    for trial, order in enumerate(orders, 1):
        for case in (cases if trial % 2 else list(reversed(cases))):
            for index in order:
                label = labels[index]; name = str(trial) + '-' + case + '-' + label
                command = [build['binaries'][label]['path'], 'benchmark', str(fixtures), case]
                entry = {'round': trial, 'case': case, 'label': label, 'command': command,
                         'startedUTC': now(), 'hostLoadBefore': os.getloadavg(),
                         'stdout': name + '.stdout.jsonl', 'stderr': name + '.stderr.log'}
                result['records'].append(entry); save()
                with (out / entry['stdout']).open('w') as stdout, (out / entry['stderr']).open('w') as stderr:
                    process = subprocess.run(command, stdout=stdout, stderr=stderr)
                entry.update(exitCode=process.returncode, finishedUTC=now(), hostLoadAfter=os.getloadavg()); save()
                assert process.returncode == 0
                rows = [json.loads(line) for line in (out / entry['stdout']).read_text().splitlines()]
                assert len(rows) == 1 and rows[0]['case'] == case and rows[0]['pixelExact'] and len(rows[0]['samplesSeconds']) == 20
                entry['result'] = rows[0]; save()
            print('Completed round', trial, case, flush=True)
    result['inputsUnchanged'] = all(sha(p) == h for p, h in pins.items()) and all(unchanged(v) for v in build['imports'].values())
    assert result['inputsUnchanged']; result['status'] = 'complete'
except BaseException as error:
    result['status'] = 'failed'; result['error'] = repr(error); raise
finally:
    result['finishedUTC'] = now(); save()
