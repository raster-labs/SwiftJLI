#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Require all six Release Watch simulator cases; this never qualifies a device."""
import argparse
import hashlib
import json
import math
import os
import re
import signal
import subprocess
from pathlib import Path

CASES = {
    'profile-and-decoded-boundary', 'repeated-lossless-caller-storage',
    'concurrent-readers', 'dct-watch-budgets', 'workspace-denial-and-recovery',
    'cancellation-deadline-recovery',
}
BUDGETS = {
    'maximumCompressedBytes': 16 * 1024 * 1024,
    'maximumDecodedBytes': 32 * 1024 * 1024,
    'maximumWorkspaceBytes': 32 * 1024 * 1024,
    'maximumMemoryBytes': 64 * 1024 * 1024,
    'maximumWorkers': 2,
    'deadlineSeconds': 30,
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(report, summary, log):
    """Validate parsed evidence; fixture checks use this without invoking Xcode."""
    for key, expected in {'status': 'passed', 'configuration': 'Release',
                          'platform': 'watchOS Simulator', 'scheme': 'WatchQualification-Package',
                          'testsPassed': 6}.items():
        require(report.get(key) == expected, f'Runner {key} must be {expected!r}')
    commands = report.get('commands', [])
    require(bool(commands), 'Runner has no command receipts')
    require(all(type(c.get('exit_code')) is int and c['exit_code'] == 0 for c in commands),
            'Every runner command must have a successful exit receipt')
    test_commands = [c['argv'] for c in commands if c.get('name') == 'test']
    require(len(test_commands) == 1, 'Exactly one test command is required')
    command = test_commands[0]
    for flag, value in [('-configuration', 'Release'), ('-scheme', 'WatchQualification-Package')]:
        require(command.count(flag) == 1 and command.index(flag) + 1 < len(command)
                and command[command.index(flag) + 1] == value, f'Test argv must select {flag} {value}')
    device = report.get('device', {})
    device_id = device.get('udid')
    require(isinstance(device_id, str) and bool(device_id), 'Runner simulator device ID is missing')
    expected_destination = 'platform=watchOS Simulator,id=' + device_id
    require(command.count('-destination') == 1 and command.index('-destination') + 1 < len(command)
            and command[command.index('-destination') + 1] == expected_destination,
            'Test argv must select the recorded Watch simulator')
    runtime = re.fullmatch(r'com\.apple\.CoreSimulator\.SimRuntime\.watchOS-(\d+(?:-\d+)*)', report.get('runtime', ''))
    require(runtime is not None and int(runtime[1].split('-')[0]) >= 26, 'Watch runtime must be OS 26 or later')

    for key, expected in {'result': 'Passed', 'totalTestCount': 6, 'passedTests': 6,
                          'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}.items():
        require(summary.get(key) == expected, f'xcresult {key} must be {expected!r}')
    require(summary.get('testFailures') == [], 'xcresult must contain no failure records')
    configurations = summary.get('devicesAndConfigurations', [])
    require(len(configurations) == 1, 'Exactly one xcresult simulator configuration is required')
    configuration = configurations[0]
    for key, expected in {'passedTests': 6, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}.items():
        require(configuration.get(key) == expected, f'xcresult device {key} must be {expected}')
    result_device = configuration.get('device', {})
    require(result_device.get('platform') == 'watchOS Simulator', 'xcresult environment is not a Watch simulator')
    require(result_device.get('deviceId') == device_id, 'xcresult and runner simulator IDs differ')
    os_version = re.fullmatch(r'\d+(?:\.\d+)*', result_device.get('osVersion', ''))
    require(os_version is not None, 'xcresult Watch OS version is missing or malformed')
    def version_parts(value, separator):
        parts = [int(x) for x in value.split(separator)]
        while len(parts) > 1 and parts[-1] == 0:
            parts.pop()
        return parts
    require(version_parts(runtime[1], '-') == version_parts(os_version[0], '.'),
            'xcresult OS version differs from the recorded Watch runtime')

    records = []
    for line in log.splitlines():
        if 'WATCH_QUALIFICATION ' in line:
            value = json.loads(line.split('WATCH_QUALIFICATION ', 1)[1])
            require(isinstance(value, dict), 'Watch record must be a JSON object')
            records.append(value)
    require(len(records) == 6, 'Exactly six WATCH_QUALIFICATION records are required')
    require({r.get('case') for r in records} == CASES, 'Watch case names must be the six unique expected cases')
    for record in records:
        require(record.get('environment') == 'watch-simulator', 'Every Watch record must identify watch-simulator')
        for key, expected in BUDGETS.items():
            value = record.get(key)
            require(type(value) in (int, float) and value == expected, f'Watch budget changed: {key}')
        elapsed = record.get('elapsedSeconds')
        require(type(elapsed) in (int, float) and math.isfinite(elapsed) and elapsed >= 0,
                'Watch elapsed time must be finite and nonnegative')
        rss = record.get('processPeakRSSBytes')
        require(type(rss) is int and rss >= 0, 'Watch RSS observation must be nonnegative')
        require(isinstance(record.get('os'), str) and bool(record['os']), 'Watch record OS is missing')
    return records


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_source_identity(repository, paths, tree_output):
    """Compare working bytes with Git object identities, including added/deleted files."""
    wanted = {str(p.relative_to(repository)) for p in paths}
    expected = {}
    for entry in tree_output.split('\0'):
        if not entry:
            continue
        metadata, name = entry.split('\t', 1)
        mode, kind, object_id = metadata.split()
        if name in wanted or (name.startswith('Sources/') and name.endswith('.swift')):
            require(kind == 'blob' and mode in ('100644', '100755'), 'Source must be a regular Git blob: ' + name)
            expected[name] = object_id
    require(set(expected) == wanted, 'Captured source paths differ from the revision tree')
    for name, object_id in expected.items():
        path = repository / name
        require(not path.is_symlink(), 'Source cannot be a symlink: ' + name)
        data = path.read_bytes()
        actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        require(actual == object_id, 'Source bytes differ from the recorded revision: ' + name)
    return expected


def bundle_hashes(bundle):
    paths = sorted(p for p in bundle.rglob('*') if p.is_file())
    require(bool(paths), 'xcresult bundle contains no files')
    require(not any(p.is_symlink() for p in paths), 'xcresult bundle must not contain symlink files')
    return {str(p.relative_to(bundle)): sha(p) for p in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--output', type=Path, help='Fresh output directory; defaults to EVIDENCE/verification')
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    out = (args.output or evidence / 'verification').resolve()
    out.mkdir(parents=True, exist_ok=False)
    receipt = {'status': 'running', 'scope': 'watch-simulator only; no physical-device or RSS-ceiling qualification',
               'helperSHA256': sha(Path(__file__)), 'commands': []}

    def save():
        (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def run(name, argv, timeout):
        with (out / (name + '.stdout')).open('wb') as stdout, (out / (name + '.stderr')).open('wb') as stderr:
            proc = subprocess.Popen(argv, stdout=stdout, stderr=stderr, start_new_session=True)
            timed_out = False
            try:
                code = proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                os.killpg(proc.pid, signal.SIGTERM)
                try:
                    code = proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    code = proc.wait(timeout=5)
        receipt['commands'].append({'argv': argv, 'exitCode': code, 'timeoutSeconds': timeout,
                                    'timedOut': timed_out, 'stdout': name + '.stdout', 'stderr': name + '.stderr',
                                    'stdoutSHA256': sha(out / (name + '.stdout')), 'stderrSHA256': sha(out / (name + '.stderr'))})
        save()
        require(code == 0 and not timed_out, f'{name} failed or timed out')
        return (out / (name + '.stdout')).read_text()

    try:
        report_path, log_path, bundle = evidence / 'report.json', evidence / 'test.log', evidence / 'Tests.xcresult'
        receipt['inputs'] = {'report.json': sha(report_path), 'test.log': sha(log_path)}
        receipt['xcresultFilesSHA256'] = bundle_hashes(bundle)
        report = json.loads(report_path.read_text())
        repository = Path(__file__).resolve().parent.parent
        head = run('revision', ['git', '-C', str(repository), 'rev-parse', 'HEAD'], 15).strip()
        require(report.get('revision') == head, 'Runner revision differs from the inspected checkout')
        receipt['revision'] = head
        source_paths = sorted((repository / 'Sources').rglob('*.swift')) + [
            repository / 'Package.swift',
            repository / 'Examples/WatchQualification/Package.swift',
            repository / 'Examples/WatchQualification/Tests/WatchQualificationTests/WatchQualificationTests.swift']
        tree = run('source-tree', ['git', '-C', str(repository), 'ls-tree', '-rz', '--full-tree', head,
            '--', 'Sources', 'Package.swift', 'Examples/WatchQualification/Package.swift',
            'Examples/WatchQualification/Tests/WatchQualificationTests/WatchQualificationTests.swift'], 15)
        receipt['sourceGitBlobSHA1'] = validate_source_identity(repository, source_paths, tree)
        receipt['sourceMatchesRevision'] = True
        receipt['sourceSHA256'] = {str(p.relative_to(repository)): sha(p) for p in source_paths}
        summary_text = run('xcresult-summary', ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                               '--path', str(bundle)], 120)
        summary = json.loads(summary_text)
        (out / 'xcresult-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        receipt['summarySHA256'] = sha(out / 'xcresult-summary.json')
        records = validate(report, summary, log_path.read_text())
        (out / 'watch-records.json').write_text(json.dumps(records, indent=2) + '\n')
        receipt['recordsSHA256'] = sha(out / 'watch-records.json')
        require(receipt['inputs'] == {'report.json': sha(report_path), 'test.log': sha(log_path)}, 'Runner evidence changed during verification')
        require(receipt['xcresultFilesSHA256'] == bundle_hashes(bundle), 'xcresult changed during verification')
        require(all(sha(repository / p) == h for p, h in receipt['sourceSHA256'].items()), 'Source changed during verification')
        receipt.update(status='passed', testsPassed=6, testsFailed=0, testsSkipped=0, records=6,
                       environment='watch-simulator', configuration='Release', inputsUnchanged=True)
        save()
        print('Watch simulator qualification passed: six Release tests and six verified records; no device qualification.')
    except Exception as error:
        receipt.update(status='failed', error=str(error))
        save()
        raise


if __name__ == '__main__':
    main()
