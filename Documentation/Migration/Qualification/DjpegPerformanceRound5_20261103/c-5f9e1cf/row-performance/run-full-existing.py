"""Run full lossless sequence with the exact binaries used by the targeted gate."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import subprocess

root = Path(__file__).resolve().parent
targeted = json.loads((root / 'targeted-results.json').read_text())
assert targeted['status'] == 'complete'
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
binaries = {name: root / ('targeted-' + name) for name in ['baseline', 'candidate']}
assert all(sha(binary) == targeted['binarySHA256'][name] for name, binary in binaries.items())
fixtures = Path('/private/tmp/swiftjli-native-matrix-fixtures')
output = root / 'lossless-same-binaries.json'
result = {
    'status': 'running', 'startedUTC': now(),
    'baselineRevision': targeted['baselineRevision'],
    'candidateRevision': targeted['candidateRevision'],
    'method': 'Same linked executables as targeted gate, without the optional case filter. '
              'Full16-case sequence per process;5 warmups and20 samples per case; '
              'two rounds with binary order reversed. Exactness remains outside timing.',
    'timingStatus': 'Provisional shared-host measurements; separate method, not pooled with targeted pairs.',
    'sourceTargetedReceiptSHA256': sha(root / 'targeted-results.json'),
    'harnessSHA256': targeted['harnessSHA256'], 'runnerSHA256': sha(__file__),
    'compilerSHA256': targeted['compilerSHA256'],
    'binarySHA256': targeted['binarySHA256'], 'linkedObjects': targeted['objects'],
    'fixtureSHA256': {path.name: sha(path) for path in sorted(fixtures.glob('*')) if path.is_file()},
    'matrix': []
}
output.write_text(json.dumps(result, indent=2) + '\n')
with (root / 'full-existing-host.jsonl').open('w') as host:
    for round_number in [1, 2]:
        order = ['baseline', 'candidate'] if round_number == 1 else ['candidate', 'baseline']
        for name in order:
            command = [str(binaries[name]), 'benchmark', str(fixtures)]
            host.write(json.dumps({'utc': now(), 'round': round_number, 'label': name,
                'loadAverage': os.getloadavg(),
                'processes': subprocess.check_output(['ps', '-axo', 'pid,pcpu,comm'], text=True)}) + '\n')
            host.flush()
            run = subprocess.run(command, capture_output=True, text=True)
            log = root / ('full-existing-' + name + '-round' + str(round_number) + '.jsonl')
            log.write_text(run.stdout)
            receipt = {'round': round_number, 'binary': name, 'command': command,
                       'exitCode': run.returncode, 'stderr': run.stderr, 'log': str(log), 'records': []}
            result['matrix'].append(receipt)
            output.write_text(json.dumps(result, indent=2) + '\n')
            run.check_returncode()
            receipt['records'] = [json.loads(line) for line in run.stdout.splitlines() if line.strip()]
            assert len(receipt['records']) == 16
            assert all(row['pixelExact'] and len(row['samplesSeconds']) == 20 for row in receipt['records'])
            output.write_text(json.dumps(result, indent=2) + '\n')
            print('Completed', name, 'round', round_number, '16 exact cases; binary unchanged', flush=True)
assert all(sha(binary) == targeted['binarySHA256'][name] for name, binary in binaries.items())
result['status'] = 'complete'
result['finishedUTC'] = now()
output.write_text(json.dumps(result, indent=2) + '\n')
