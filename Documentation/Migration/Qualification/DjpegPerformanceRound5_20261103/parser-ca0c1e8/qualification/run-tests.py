#!/usr/bin/env python3
"""Pinned parser experiment; requires --execute and an assigned CPU slot."""
import argparse, datetime, hashlib, json, os, pathlib, re, subprocess, time
ROOT = pathlib.Path(__file__).resolve().parent
REPO = pathlib.Path('/private/tmp/swiftjli-round5-parser-reservation')
PIN = 'ca0c1e874177f429ed199f3ed8ef6ac1315ee66a'
FILTER = 'ParserReservationTests|StreamingWorkspaceAdmissionTests|ValidatedEnvelopeTests|CompressedInputOwnershipTests|JPEGDecodeParityTests|JPEGMigrationTests|LimitTests|MetadataTests|EntropyBoundaryTests'
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
sha = lambda p: hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--execute', action='store_true')
p.add_argument('--full', action='store_true')
p.add_argument('--output', type=pathlib.Path, required=True)
a = p.parse_args()
command = ['swift', 'test', '-c', 'release', '--jobs', '4', '--scratch-path',
           '/private/tmp/swiftjli-round5-parser-reservation-release-build']
if not a.full: command += ['--filter', FILTER]
if not a.execute:
    print(json.dumps({'status': 'NOT EXECUTED', 'sourceRevision': PIN, 'command': command}, indent=2))
    raise SystemExit(0)
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip() == PIN
assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=REPO)
source = json.loads((ROOT / 'source.json').read_text())
for item in source['files']: assert sha(REPO / item['path']) == item['sha256']
output = a.output.resolve(); output.mkdir(parents=True, exist_ok=False)
env = os.environ.copy(); env['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
receipt = {'sourceRevision': PIN, 'status': 'running', 'startedUTC': now(), 'command': command,
           'cwd': str(REPO), 'environmentOverrides': {'DEVELOPER_DIR': env['DEVELOPER_DIR']},
           'sourceReceiptSHA256': sha(ROOT / 'source.json'), 'runnerSHA256': sha(__file__)}
path = output / 'command.json'
path.write_text(json.dumps(receipt, indent=2) + '\n')
start = time.monotonic()
with (output / 'tests.log').open('w') as log:
    result = subprocess.run(command, cwd=REPO, env=env, stdout=log, stderr=subprocess.STDOUT)
text = (output / 'tests.log').read_text()
match = re.search(r'Test run with (\d+) tests in (\d+) suites passed', text)
receipt.update(status='passed' if result.returncode == 0 and match else 'failed',
               exitCode=result.returncode, elapsedSeconds=time.monotonic() - start,
               finishedUTC=now(), logSHA256=sha(output / 'tests.log'),
               summary={'tests': int(match[1]), 'suites': int(match[2])} if match else None)
receipt['sourceUnchanged'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip() == PIN and not subprocess.check_output(['git', 'status', '--porcelain'], cwd=REPO)
path.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
raise SystemExit(0 if receipt['status'] == 'passed' and receipt['sourceUnchanged'] else 1)
