#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Build and supervise deterministic public-entry fuzz campaigns on Linux ARM/x86.

Each entry runs for --seconds (default one hour). A stale heartbeat, crash,
internal codec error, missing completion or early completion fails the gate.
This is mutation fuzzing, not a coverage-guided campaign or security certification.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--seconds', type=int, default=3600)
    parser.add_argument('--image', default='swift:6.4-noble')
    args = parser.parse_args()
    if not 1 <= args.seconds <= 86400:
        parser.error('--seconds must be 1...86400')
    root = Path(__file__).resolve().parent.parent
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    # Separate logs prevent a prior completion record from being mistaken for this run.
    if (output / 'campaign.json').exists():
        parser.error('output directory already contains a campaign; choose a fresh directory')
    image = subprocess.check_output(['docker', 'image', 'inspect', args.image, '--format', '{{.Id}}'], text=True).strip()
    docker = ['docker', 'run', '--rm', '--ulimit', 'core=0', '-v', f'{root}:/src', '-w', '/src', image]
    # The old .build-fuzz binary may still be executing a pinned campaign.
    # New campaigns use a separate cache, then run a private executable copy so
    # later builds cannot replace the mapped binary of an active worker.
    scratch = '.build-fuzz-campaigns'
    build = ['swift', 'build', '--package-path', 'Examples/DecoderFuzz', '--scratch-path', scratch, '-c', 'release', '-j', '4']
    def source_hashes():
        files = [root / 'Package.swift'] + sorted((root / 'Sources').rglob('*.swift')) + [root / 'Examples/DecoderFuzz/Package.swift'] + sorted((root / 'Examples/DecoderFuzz/Sources').rglob('*.swift'))
        return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    sources = source_hashes()
    with (output / 'build.log').open('w') as log:
        subprocess.run(docker + build, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
    if source_hashes() != sources:
        raise RuntimeError('Sources changed during fuzz build; no campaign was started')
    binary = output / 'DecoderFuzz'
    shutil.copy2(root / scratch / 'release/DecoderFuzz', binary)
    record = {
        'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
        'working_tree_status': subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True),
        'source_hashes': sources, 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'binary_path': str(binary), 'supervisor_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'compiler': subprocess.check_output(docker + ['swift', '--version'], text=True).strip(),
        'image_id': image, 'seconds_per_entry': args.seconds, 'build_command': build,
        'campaign_type': 'deterministic mutation, scalar, release without sanitizers', 'entries': []}
    children = []
    try:
        for entry in ('inspect', 'inspectJPEG', 'allocate', 'destination'):
            name = f'swiftjli-fuzz-{entry}-{uuid.uuid4().hex[:12]}'
            log_path = output / f'{entry}.jsonl'
            log = log_path.open('w')
            command = ['docker', 'run', '--rm', '--name', name, '--cpus', '1', '--memory', '256m', '--ulimit', 'core=0',
                '-v', f'{root}:/src:ro', '-v', f'{output}:/evidence', image,
                '/evidence/DecoderFuzz', entry, str(args.seconds), f'/evidence/{entry}-failure.bin']
            child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            children.append((child, log, log_path, name))
            record['entries'].append({'entry': entry, 'command': command, 'status': 'running'})
        (output / 'campaign.json').write_text(json.dumps(record, indent=2) + '\n')
        print(f'Running {len(children)} campaigns for {args.seconds}s each; evidence: {output}', flush=True)
        started = time.monotonic()
        while any(child.poll() is None for child, *_ in children):
            for child, log, path, name in children:
                if child.poll() not in (None, 0):
                    raise RuntimeError(f'Fuzz process failed for {name}; inspect {path}')
                if child.poll() is None and (time.time() - path.stat().st_mtime > 30 or time.monotonic() - started > args.seconds + 60):
                    subprocess.run(['docker', 'rm', '-f', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                    raise RuntimeError(f'Fuzz watchdog expired for {name}; last checkpoint is in {path}')
            time.sleep(1)
        success = True
        for result, (child, log, path, _) in zip(record['entries'], children):
            log.close()
            lines = path.read_text().splitlines()
            events = []
            for line in lines:
                try:
                    event = json.loads(line)
                    if isinstance(event, dict): events.append(event)
                except json.JSONDecodeError:
                    pass
            complete = next((e for e in reversed(events) if e.get('event') == 'complete'), None)
            passed = child.returncode == 0 and complete is not None and complete['elapsed_seconds'] >= args.seconds and complete['accepted'] > 0 and complete['rejected'] > 0
            result.update(status='passed' if passed else 'failed', exit_code=child.returncode, completion=complete,
                          log_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
            success = success and passed
            print(f'{result["entry"]}: {result["status"]}, {complete}', flush=True)
        record['status'] = 'passed' if success else 'failed'
        if not success:
            raise RuntimeError('Fuzz campaign failed; inspect per-entry logs')
    except BaseException as error:
        record['status'] = 'failed'
        record['supervisor_error'] = str(error)
        raise
    finally:
        for result, (child, log, _, name) in zip(record['entries'], children):
            if child.poll() is None:
                subprocess.run(['docker', 'rm', '-f', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                child.wait(timeout=30)
            if not log.closed: log.close()
            if result['status'] == 'running':
                result.update(status='aborted', exit_code=child.poll())
        (output / 'campaign.json').write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
