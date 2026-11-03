#!/usr/bin/env python3
"""Run only after the parent grants CPU; preserve every attempted action."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['build-helper', 'retained', 'focused'])
    parser.add_argument('--run', required=True)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--cpu-grant', required=True)
    args = parser.parse_args()
    if not args.execute or not args.cpu_grant.strip():
        parser.error('Explicit execution and parent CPU grant are required.')
    if Path(args.run).name != args.run or args.run in ('.', '..'):
        parser.error('run must be one path component')
    plan_path = HERE / 'prepared.json'
    plan = json.loads(plan_path.read_text())
    for path, expected in plan['inputs'].items():
        if digest(path) != expected:
            raise RuntimeError('Changed pinned input: ' + path)
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=plan['candidateWorktree'], text=True).strip()
    if head != plan['candidateRevision']:
        raise RuntimeError('Candidate HEAD changed')
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=plan['candidateWorktree'], text=True).strip():
        raise RuntimeError('Candidate worktree is dirty')
    run_dir = HERE / 'runs' / args.run
    run_dir.mkdir(parents=True, exist_ok=True)
    receipt_path = run_dir / (args.action + '.json')
    log_path = run_dir / (args.action + '.log')
    if receipt_path.exists() or log_path.exists():
        raise RuntimeError('Action output already exists; choose a fresh run')
    helper = run_dir / 'swiftpm-testing-helper-x86_64'
    env = os.environ.copy()
    env['DEVELOPER_DIR'] = plan['developerDirectory']
    if args.action == 'build-helper':
        if helper.exists():
            raise RuntimeError('Helper already exists')
        command = [plan['swiftc'], '-parse-as-library', '-O', '-target',
            'x86_64-apple-macos26.0', '-sdk', plan['sdk'],
            str(HERE / 'Entrypoint.swift'), '-o', str(helper)]
        cwd, timeout = str(HERE), 180
    elif args.action == 'retained':
        built = json.loads((run_dir / 'build-helper.json').read_text())
        if built.get('exitCode') != 0 or built.get('outputs', {}).get(str(helper)) != digest(helper):
            raise RuntimeError('Matching successful helper build receipt required')
        env['DYLD_FRAMEWORK_PATH'] = plan['frameworkDirectory']
        command = ['/usr/bin/arch', '-x86_64', str(helper), '--test-bundle-path',
            plan['retainedBinary'], '--testing-library', 'swift-testing',
            '--filter', 'CACPublicPipelineTests']
        cwd, timeout = str(run_dir), 240
    else:
        command = [plan['swift'], 'test', '-c', 'release', '--jobs', '4',
            '--scratch-path', plan['candidateScratch'], '--filter', 'CACPublicPipelineTests']
        cwd, timeout = plan['candidateWorktree'], 2400
    receipt = {
        'action': args.action, 'scope': plan['scopes'][args.action],
        'parentCPUGrant': args.cpu_grant, 'preparedSHA256': digest(plan_path),
        'candidateRevision': head, 'command': command, 'cwd': cwd,
        'environmentOverrides': {k: env[k] for k in ('DEVELOPER_DIR', 'DYLD_FRAMEWORK_PATH') if k in env},
        'startedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'exitCode': None, 'inputs': plan['inputs'], 'outputs': {},
        'qualificationLimits': plan['qualificationLimits'],
    }
    write_json(receipt_path, receipt)
    started = time.monotonic()
    with log_path.open('wb') as log:
        try:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=log,
                stderr=subprocess.STDOUT, timeout=timeout)
            receipt['exitCode'] = result.returncode
        except subprocess.TimeoutExpired:
            receipt['failure'] = 'Timed out; this is not a passed test'
        except OSError as error:
            receipt['failure'] = str(error)
    receipt['elapsedSeconds'] = time.monotonic() - started
    receipt['finishedUTC'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    receipt['logSHA256'] = digest(log_path)
    receipt['inputHashesUnchanged'] = all(digest(p) == h for p, h in plan['inputs'].items())
    if helper.exists():
        receipt['outputs'][str(helper)] = digest(helper)
    write_json(receipt_path, receipt)
    print(json.dumps({'receipt': str(receipt_path), 'exitCode': receipt['exitCode'],
        'inputHashesUnchanged': receipt['inputHashesUnchanged']}), flush=True)
    return 0 if receipt['exitCode'] == 0 and receipt['inputHashesUnchanged'] else 1

if __name__ == '__main__':
    sys.exit(main())
