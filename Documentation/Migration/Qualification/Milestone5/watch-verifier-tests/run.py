#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Synthetic verifier fixtures only: no simulator, Xcode tests or device results."""
import argparse
import copy
import hashlib
import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--repository', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
a = p.parse_args()
out = a.output.resolve()
out.mkdir(parents=True, exist_ok=False)
helper = a.repository.resolve() / 'Scripts/verify-watch-qualification.py'
spec = importlib.util.spec_from_file_location('watch_verifier', helper)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
udid = '00000000-0000-0000-0000-000000000026'
report = {'status': 'passed', 'configuration': 'Release', 'platform': 'watchOS Simulator',
    'scheme': 'WatchQualification-Package', 'testsPassed': 6, 'device': {'udid': udid},
    'runtime': 'com.apple.CoreSimulator.SimRuntime.watchOS-26-0',
    'commands': [{'name': 'test', 'exit_code': 0, 'argv': ['xcodebuild', 'test', '-configuration', 'Release',
        '-scheme', 'WatchQualification-Package', '-destination', 'platform=watchOS Simulator,id=' + udid]}]}
summary = {'result': 'Passed', 'totalTestCount': 6, 'passedTests': 6, 'failedTests': 0,
    'skippedTests': 0, 'expectedFailures': 0, 'testFailures': [], 'devicesAndConfigurations': [{
        'passedTests': 6, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0,
        'device': {'deviceId': udid, 'platform': 'watchOS Simulator', 'osVersion': '26.0'}}]}
records = [{'case': case, 'environment': 'watch-simulator', 'os': 'MOCK watchOS 26.0',
            'elapsedSeconds': 0.1, 'processPeakRSSBytes': 1, **module.BUDGETS} for case in sorted(module.CASES)]
results = []
def check(name, mutate=None):
    r, s, records_copy = copy.deepcopy((report, summary, records))
    if mutate:
        mutate(r, s, records_copy)
    log = '\n'.join('WATCH_QUALIFICATION ' + json.dumps(value) for value in records_copy)
    error = None
    try:
        module.validate(r, s, log)
    except (ValueError, KeyError, TypeError) as exc:
        error = str(exc)
    expected = 'rejected' if mutate else 'accepted'
    actual = 'rejected' if error else 'accepted'
    results.append({'fixture': name, 'expected': expected, 'actual': actual, 'error': error})
    assert actual == expected, name
check('positive mock')
check('missing case', lambda r,s,v: v.pop())
check('duplicate case', lambda r,s,v: v[0].update(case=v[1]['case']))
check('host record environment', lambda r,s,v: v[0].update(environment='host-harness-check'))
check('physical record environment', lambda r,s,v: v[0].update(environment='physical-watch'))
check('skipped summary', lambda r,s,v: s.update(skippedTests=1))
check('failed summary', lambda r,s,v: s.update(failedTests=1, result='Failed'))
check('skipped device summary', lambda r,s,v: s['devicesAndConfigurations'][0].update(skippedTests=1))
check('failed device summary', lambda r,s,v: s['devicesAndConfigurations'][0].update(failedTests=1))
check('physical xcresult', lambda r,s,v: s['devicesAndConfigurations'][0]['device'].update(platform='watchOS'))
check('different xcresult device', lambda r,s,v: s['devicesAndConfigurations'][0]['device'].update(deviceId='other'))
check('different xcresult OS version', lambda r,s,v: s['devicesAndConfigurations'][0]['device'].update(osVersion='27.0'))
check('old Watch runtime', lambda r,s,v: r.update(runtime='com.apple.CoreSimulator.SimRuntime.watchOS-25-0'))
check('failed runner command', lambda r,s,v: r['commands'][0].update(exit_code=1))
check('missing command exit', lambda r,s,v: r['commands'][0].pop('exit_code'))
check('Debug runner', lambda r,s,v: r.update(configuration='Debug'))
check('Debug invocation', lambda r,s,v: r['commands'][0]['argv'].__setitem__(3, 'Debug'))
check('wrong suite count', lambda r,s,v: s.update(passedTests=5, totalTestCount=5))
check('unknown case', lambda r,s,v: v[0].update(case='invented'))
check('extra record', lambda r,s,v: v.append(copy.deepcopy(v[0])))
check('missing budget', lambda r,s,v: v[0].pop('maximumMemoryBytes'))
check('nonfinite timing', lambda r,s,v: v[0].update(elapsedSeconds=float('nan')))
for key in module.BUDGETS:
    check('budget drift ' + key, lambda r,s,v,key=key: v[0].update({key: module.BUDGETS[key] + 1}))
source_root = out / 'mock-source'
(source_root / 'Sources').mkdir(parents=True)
mock_source, mock_manifest = source_root / 'Sources/Mock.swift', source_root / 'Package.swift'
mock_source.write_text('// MOCK source identity fixture, not compiled\n')
mock_manifest.write_text('// MOCK manifest identity fixture, not compiled\n')
source_paths = [mock_source, mock_manifest]
tree = ''.join('100644 blob ' + subprocess.check_output(['git', 'hash-object', str(path)], text=True).strip()
               + '\t' + str(path.relative_to(source_root)) + '\0' for path in source_paths)
module.validate_source_identity(source_root, source_paths, tree)
source_checks = [{'fixture': 'matching Git objects', 'expected': 'accepted', 'actual': 'accepted'}]
for name, paths, change in [
    ('dirty same-revision Swift bytes', source_paths, mock_source),
    ('dirty same-revision root manifest', source_paths, mock_manifest),
    ('missing tracked Swift path', [mock_manifest], None),
]:
    original = change.read_bytes() if change else None
    if change:
        change.write_bytes(original + b'// changed\n')
    try:
        module.validate_source_identity(source_root, paths, tree)
    except ValueError as error:
        source_checks.append({'fixture': name, 'expected': 'rejected', 'actual': 'rejected', 'error': str(error)})
    else:
        raise AssertionError(name)
    finally:
        if change:
            change.write_bytes(original)
original_bundle = out / 'mock-original.xcresult'
original_bundle.mkdir()
(original_bundle / 'Info.plist').write_text('MOCK immutable bundle payload\n')
copy_bundle = out / 'mock-copy.xcresult'
before = module.bundle_hashes(original_bundle)
shutil.copytree(original_bundle, copy_bundle)
copy_before = module.bundle_hashes(copy_bundle)
(copy_bundle / 'database.sqlite3').write_text('MOCK xcresulttool index\n')
copy_after = module.bundle_hashes(copy_bundle)
module.validate_bundle_query(before, module.bundle_hashes(original_bundle), copy_before, copy_after)
bundle_checks = [{'fixture': 'index creation on copied bundle', 'expected': 'accepted', 'actual': 'accepted'}]
for name, original_after, changed_copy in [
    ('original payload mutation', {**before, 'Info.plist': 'changed'}, copy_after),
    ('copied payload mutation', before, {**copy_after, 'Info.plist': 'changed'}),
    ('original new cache file', {**before, 'database.sqlite3': 'new'}, copy_after),
]:
    try:
        module.validate_bundle_query(before, original_after, copy_before, changed_copy)
    except ValueError as error:
        bundle_checks.append({'fixture': name, 'expected': 'rejected', 'actual': 'rejected', 'error': str(error)})
    else:
        raise AssertionError(name)
protected = out / 'already-exists'; protected.mkdir(); marker = protected / 'sentinel'; marker.write_text('preserve fixture\n')
command = [sys.executable, str(helper), '--evidence', str(out / 'no-real-evidence'), '--output', str(protected)]
proc = subprocess.run(command, capture_output=True, text=True, timeout=10)
assert proc.returncode != 0 and marker.read_text() == 'preserve fixture\n'
assert sorted(x.name for x in protected.iterdir()) == ['sentinel']
result = {'status': 'passed', 'scope': 'MOCK fixtures only; no genuine Watch runtime/test evidence',
    'helperSHA256': hashlib.sha256(helper.read_bytes()).hexdigest(),
    'fixtureRunnerSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'fixtures': results, 'positiveMocks': 1, 'negativeMocks': len(results)-1,
    'sourceIdentityFixtures': source_checks,
    'bundleCopyFixtures': bundle_checks,
    'existingOutputGuard': {'command': command, 'exitCode': proc.returncode, 'stderr': proc.stderr, 'sentinelUnchanged': True}}
reference = a.repository.resolve() / 'Documentation/Migration/Qualification/Milestone5/ci/test-isolation/visionos-xcresult-summary.json'
result['summaryFieldShapeReference'] = {'path': str(reference.relative_to(a.repository.resolve())),
    'sha256': hashlib.sha256(reference.read_bytes()).hexdigest(),
    'scope': 'Field shape from a real hosted visionOS xcresult summary; all six-test Watch fixture values remain synthetic.'}
(out / 'report.json').write_text(json.dumps(result, indent=2) + '\n')
print(f'MOCK fixtures passed: 1 positive, {len(results)-1} negative; existing output preserved. No Watch execution.')
