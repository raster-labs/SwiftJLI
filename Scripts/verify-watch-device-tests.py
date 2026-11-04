#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verify six physical Watch tests; resource-ceiling/release acceptance is separate."""
import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys

sys.dont_write_bytecode = True
SHARED_PATH = Path(__file__).resolve().with_name('verify-watch-qualification.py')
spec = importlib.util.spec_from_file_location('watch_evidence_utilities', SHARED_PATH)
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)
require, sha = shared.require, shared.sha
CAPTURE_FILES = ('test.log', 'test.stderr', 'devices.json', 'xcode.log', 'compiler.log', 'sdk.log')


def source_hashes(repository):
    paths = sorted((repository / 'Sources').rglob('*.swift')) + [
        repository / 'Package.swift', repository / 'Examples/WatchQualification/Package.swift',
        repository / 'Examples/WatchQualification/Tests/WatchQualificationTests/WatchQualificationTests.swift']
    return {str(p.relative_to(repository)): sha(p) for p in paths}


def version(value):
    require(isinstance(value, str) and re.fullmatch(r'\d+(?:\.\d+)*', value), 'Malformed OS version')
    parts = [int(x) for x in value.split('.')]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return parts


def validate_capture_paths(report):
    """Bind original execution paths; the complete evidence directory may relocate."""
    paths = report.get('capturePaths', {})
    for key in ('repository', 'evidence', 'resultBundle'):
        value = paths.get(key)
        require(isinstance(value, str) and Path(value).is_absolute()
                and '..' not in Path(value).parts and str(Path(value)) == value,
                'Capture must retain a normalised absolute ' + key + ' path')
    tests = [c for c in report.get('commands', []) if c.get('name') == 'test']
    require(len(tests) == 1, 'Exactly one test command is required')
    test = tests[0]
    require(test.get('cwd') == str(Path(paths['repository']) / 'Examples/WatchQualification'),
            'Test cwd does not match the captured repository Watch package')
    expected = str(Path(paths['evidence']) / 'Tests.xcresult')
    require(paths['resultBundle'] == expected, 'Captured result bundle is not the evidence Tests.xcresult')
    command = test.get('argv', [])
    require(command.count('-resultBundlePath') == 1 and command.index('-resultBundlePath') + 1 < len(command)
            and command[command.index('-resultBundlePath') + 1] == expected,
            'Test -resultBundlePath does not match the captured Tests.xcresult')
    return test


def validate_capture_hashes(report, input_hashes, bundle_hashes):
    test = validate_capture_paths(report)
    require(report.get('captureSHA256') == input_hashes and set(input_hashes) == set(CAPTURE_FILES),
            'Supplied files differ from capture-time hashes or the capture is incomplete')
    for stream, filename in [('stdout', 'test.log'), ('stderr', 'test.stderr')]:
        require(test.get(stream) == filename and test.get(stream + 'SHA256') == input_hashes[filename],
                'Test ' + stream + ' does not match its captured file')
    require(bool(bundle_hashes) and report.get('xcresultFilesSHA256') == bundle_hashes,
            'Supplied xcresult differs from the capture-time original bundle')


def physical_device(inventory, identifier):
    require(isinstance(inventory, list) and all(isinstance(d, dict) for d in inventory), 'Expected raw xcdevice JSON array')
    selected = [d for d in inventory if d.get('identifier') == identifier]
    require(len(selected) == 1, 'Exactly one matching inventory device is required')
    device = selected[0]
    require(device.get('simulator') is False and device.get('platform') == 'com.apple.platform.watchos',
            'Inventory must identify physical watchOS hardware')
    require(device.get('available') is True and not device.get('error'), 'Physical Watch is unavailable')
    require(device.get('architecture') in ('arm64', 'arm64e', 'arm64_32'), 'Physical Watch must have an ARM architecture')
    require(re.fullmatch(r'Watch\d+,\d+', device.get('modelCode', '')) is not None, 'Watch hardware model code is missing')
    require(isinstance(device.get('modelName'), str) and 'Watch' in device['modelName'], 'Watch model name is missing')
    match = re.fullmatch(r'(\d+(?:\.\d+)*) \(([^()\s]+)\)', device.get('operatingSystemVersion', ''))
    require(match is not None and version(match[1])[0] >= 26, 'Physical Watch OS 26+ version/build is required')
    return device, match[1], match[2]


def validate_records(log, expected_os=None, expected_build=None):
    records = [json.loads(line.split('WATCH_QUALIFICATION ', 1)[1])
               for line in log.splitlines() if 'WATCH_QUALIFICATION ' in line]
    require(len(records) == 6 and all(isinstance(r, dict) for r in records), 'Exactly six JSON Watch records are required')
    require({r.get('case') for r in records} == shared.CASES, 'Six unique expected Watch cases are required')
    for record in records:
        require(record.get('environment') == 'physical-watch', 'Every record must identify physical-watch')
        for key, expected in shared.BUDGETS.items():
            value = record.get(key)
            require(type(value) in (int, float) and value == expected, 'Watch budget changed: ' + key)
        elapsed = record.get('elapsedSeconds')
        require(type(elapsed) in (int, float) and math.isfinite(elapsed) and elapsed >= 0, 'Invalid elapsed time')
        require(type(record.get('processPeakRSSBytes')) is int and record['processPeakRSSBytes'] >= 0, 'Invalid RSS observation')
        os_text = record.get('os')
        require(isinstance(os_text, str), 'Watch record OS is missing')
        parsed = re.fullmatch(r'Version (\d+(?:\.\d+)*) \(Build ([A-Za-z0-9.]+)\)', os_text)
        require(parsed is not None, 'Unrecognised Watch record OS version/build; inspect genuine evidence')
        if expected_os is not None:
            require(version(parsed[1]) == version(expected_os) and parsed[2] == expected_build,
                    'Watch record OS version/build differs from hardware inventory')
    return records


def validate(report, summary, log, inventory):
    require(isinstance(report, dict) and isinstance(summary, dict), 'Expected capture and summary JSON objects')
    for key, expected in {'status': 'completed', 'platform': 'watchOS', 'configuration': 'Release',
                          'scheme': 'WatchQualification-Package', 'packagePath': 'Examples/WatchQualification'}.items():
        require(report.get(key) == expected, f'Capture {key} must be {expected!r}')
    commands = report.get('commands', [])
    require(isinstance(commands, list) and commands and all(isinstance(c, dict)
            and type(c.get('exit_code')) is int and c['exit_code'] == 0 and c.get('timedOut') is False for c in commands),
            'Every captured command must exit zero')
    validate_capture_paths(report)
    for name, argv in [('xcode', ['xcodebuild', '-version']), ('compiler', ['xcrun', 'swift', '--version']),
                       ('sdk', ['xcrun', '--sdk', 'watchos', '--show-sdk-version']),
                       ('devices', ['xcrun', 'xcdevice', 'list', '--timeout', '15'])]:
        entries = [c for c in commands if c.get('name') == name]
        require(len(entries) == 1 and entries[0].get('argv') == argv, 'Missing exact metadata command: ' + name)
    tests = [c['argv'] for c in commands if c.get('name') == 'test']
    require(len(tests) == 1, 'Exactly one test command is required')
    command = tests[0]
    require(len(command) >= 2 and Path(command[0]).name == 'xcodebuild' and command[1] == 'test', 'Expected xcodebuild test')
    identifier = report.get('device', {}).get('udid')
    require(isinstance(identifier, str) and bool(identifier), 'Physical destination ID is missing')
    for flag, value in [('-scheme', 'WatchQualification-Package'), ('-configuration', 'Release'),
                        ('-destination', 'platform=watchOS,id=' + identifier), ('-parallel-testing-enabled', 'NO')]:
        require(command.count(flag) == 1 and command.index(flag) + 1 < len(command)
                and command[command.index(flag) + 1] == value, f'Test command must select {flag} {value}')
    require(not any(x.startswith(('CODE_SIGNING_ALLOWED=NO', '-skip-testing', '-only-testing', '-test-iterations',
                                 '-retry-tests-on-failure', '-run-tests-until-failure', '-project', '-workspace',
                                 '-xctestrun')) for x in command),
            'Disabled signing, filtered/retried tests or an alternate project are not accepted')
    inventory_device, os_version, os_build = physical_device(inventory, identifier)
    for key, expected in {'result': 'Passed', 'totalTestCount': 6, 'passedTests': 6,
                          'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}.items():
        require(summary.get(key) == expected and (type(summary[key]) is int if isinstance(expected, int) else True),
                f'xcresult {key} must be {expected!r}')
    require(summary.get('testFailures') == [], 'xcresult contains failures')
    configurations = summary.get('devicesAndConfigurations', [])
    require(len(configurations) == 1, 'Exactly one physical Watch configuration is required')
    configuration = configurations[0]
    for key, expected in {'passedTests': 6, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}.items():
        require(type(configuration.get(key)) is int and configuration[key] == expected, 'Device test count mismatch: ' + key)
    device = configuration.get('device', {})
    require(device.get('platform') == 'watchOS', 'xcresult must identify physical watchOS, never a simulator')
    require(device.get('deviceId') == identifier, 'xcresult and inventory device IDs differ')
    require(device.get('architecture') == inventory_device['architecture'], 'xcresult hardware architecture differs')
    require(device.get('modelName') == inventory_device['modelName'], 'xcresult hardware model differs')
    require(version(device.get('osVersion')) == version(os_version), 'xcresult OS version differs')
    require(device.get('osBuildNumber') == os_build, 'xcresult OS build differs')
    return validate_records(log, os_version, os_build)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path, help='Fresh verification directory')
    args = parser.parse_args()
    evidence, out = args.evidence.resolve(), args.output.resolve()
    bundle = evidence / 'Tests.xcresult'
    require(not out.is_relative_to(bundle), 'Output cannot be inside the original xcresult')
    out.mkdir(parents=True, exist_ok=False)
    repository = Path(__file__).resolve().parent.parent
    receipt = {'status': 'running', 'scope': 'Six physical Watch tests only; resource ceilings and release acceptance remain separate',
               'helperSHA256': sha(Path(__file__)), 'sharedHelperSHA256': sha(SHARED_PATH), 'commands': []}

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
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    code = proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    code = proc.wait(timeout=5)
        receipt['commands'].append({'argv': argv, 'exitCode': code, 'timedOut': timed_out, 'timeoutSeconds': timeout,
                                    'stdout': name + '.stdout', 'stderr': name + '.stderr',
                                    'stdoutSHA256': sha(out / (name + '.stdout')), 'stderrSHA256': sha(out / (name + '.stderr'))})
        save()
        require(code == 0 and not timed_out, name + ' failed or timed out')
        return (out / (name + '.stdout')).read_text()

    try:
        files = ['report.json', 'test.log', 'devices.json', 'xcode.log', 'compiler.log', 'sdk.log']
        require(not any((evidence / f).is_symlink() for f in files) and not bundle.is_symlink(), 'Evidence cannot be symlinked')
        receipt['inputs'] = {f: sha(evidence / f) for f in files}
        report = json.loads((evidence / 'report.json').read_text())
        inventory = json.loads((evidence / 'devices.json').read_text())
        # Reject known simulator captures before invoking xcresulttool.
        require(report.get('platform') == 'watchOS', 'Capture is not physical watchOS evidence')
        require(not (evidence / 'test.stderr').is_symlink(), 'Evidence cannot be symlinked')
        files.append('test.stderr')
        receipt['inputs']['test.stderr'] = sha(evidence / 'test.stderr')
        receipt['xcresultFilesSHA256'] = shared.bundle_hashes(bundle)
        validate_capture_hashes(report, {f: receipt['inputs'][f] for f in CAPTURE_FILES}, receipt['xcresultFilesSHA256'])
        receipt['capturePaths'] = report['capturePaths']
        receipt['captureHashesVerified'] = True
        physical_device(inventory, report.get('device', {}).get('udid'))
        require((evidence / 'xcode.log').read_text().startswith('Xcode '), 'Xcode version evidence is missing')
        require('Swift version ' in (evidence / 'compiler.log').read_text(), 'Compiler version evidence is missing')
        require(version((evidence / 'sdk.log').read_text().strip())[0] >= 26, 'Watch SDK must support OS 26+')
        toolchain = {name: (evidence / (name + '.log')).read_text().strip() for name in ('xcode', 'compiler', 'sdk')}
        require(report.get('toolchain') == toolchain, 'Captured toolchain metadata differs from retained logs')
        receipt['toolchain'] = toolchain
        receipt['revision'] = run('revision', ['git', '-C', str(repository), 'rev-parse', 'HEAD'], 15).strip()
        require(report.get('revision') == receipt['revision'], 'Capture revision differs from the inspected checkout')
        hashes = source_hashes(repository)
        require(report.get('sourceSHA256Before') == hashes == report.get('sourceSHA256After'), 'Source changed or source capture is incomplete')
        tree = run('source-tree', ['git', '-C', str(repository), 'ls-tree', '-rz', '--full-tree', receipt['revision'],
                   '--', 'Sources', 'Package.swift', 'Examples/WatchQualification/Package.swift',
                   'Examples/WatchQualification/Tests/WatchQualificationTests/WatchQualificationTests.swift'], 15)
        receipt['sourceGitBlobSHA1'] = shared.validate_source_identity(repository, [repository / p for p in hashes], tree)
        receipt['sourceSHA256'] = hashes
        query = out / 'SummaryInput.xcresult'
        shutil.copytree(bundle, query)
        receipt['xcresultCopyInitialSHA256'] = shared.bundle_hashes(query)
        require(receipt['xcresultFilesSHA256'] == receipt['xcresultCopyInitialSHA256'] == shared.bundle_hashes(bundle), 'xcresult copy differs')
        summary = json.loads(run('xcresult-summary', ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(query)], 120))
        receipt['xcresultCopyAfterSHA256'] = shared.bundle_hashes(query)
        receipt['xcresultCopyChanges'] = shared.validate_bundle_query(receipt['xcresultFilesSHA256'], shared.bundle_hashes(bundle),
            receipt['xcresultCopyInitialSHA256'], receipt['xcresultCopyAfterSHA256'])
        records = validate(report, summary, (evidence / 'test.log').read_text(), inventory)
        for name, value in [('xcresult-summary.json', summary), ('watch-records.json', records)]:
            (out / name).write_text(json.dumps(value, indent=2) + '\n')
        receipt['summarySHA256'] = sha(out / 'xcresult-summary.json')
        receipt['recordsSHA256'] = sha(out / 'watch-records.json')
        require(receipt['inputs'] == {f: sha(evidence / f) for f in files}, 'Input evidence changed during verification')
        require(source_hashes(repository) == hashes, 'Source changed during verification')
        require(sha(Path(__file__)) == receipt['helperSHA256'] and sha(SHARED_PATH) == receipt['sharedHelperSHA256'], 'Verifier changed during verification')
        receipt.update(status='passed', testsPassed=6, testsFailed=0, testsSkipped=0, records=6,
                       environment='physical-watch', configuration='Release', inputsUnchanged=True,
                       originalXcresultUnchanged=True, resourceCeilingsQualified=False, stableReleaseQualified=False)
        save()
        print('Six physical Watch tests verified; device resource review and release acceptance remain open.')
    except Exception as error:
        receipt.update(status='failed', error=str(error))
        save()
        raise


if __name__ == '__main__':
    main()
