#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Parser/control tests only: never produce successful physical qualification."""
import copy
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'Scripts/verify-watch-device-tests.py'
spec = importlib.util.spec_from_file_location('physical_watch_verifier', HELPER)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
RETAINED = ROOT / 'Documentation/Migration/Qualification/Milestone5/ci/watch-qualification/intel-fallback/run-41622083807'


class WatchDeviceVerifierControls(unittest.TestCase):
    """Real simulator rejection plus explicitly synthetic parser/negative checks."""

    def setUp(self):
        self.report = json.loads((RETAINED / 'watch/report.json').read_text())
        self.summary = json.loads((RETAINED / 'watch/verification/xcresult-summary.json').read_text())
        self.log = gzip.decompress((RETAINED / 'watch/test.log.gz').read_bytes()).decode()

    def negative_inputs(self):
        # Deliberately synthetic setup only to reach rejection branches. Never
        # accept it as end-to-end device evidence or invoke a test runner.
        report = copy.deepcopy(self.report)
        report.update(status='completed', platform='watchOS', packagePath='Examples/WatchQualification')
        report['capturePaths'] = {'repository': '/original/SwiftJLI', 'evidence': '/original/evidence',
                                  'resultBundle': '/original/evidence/Tests.xcresult'}
        for command in report['commands']:
            command['timedOut'] = False
            if command['name'] == 'test':
                argv = command['argv']
                argv[argv.index('-destination') + 1] = 'platform=watchOS,id=' + report['device']['udid']
                argv[argv.index('-resultBundlePath') + 1] = report['capturePaths']['resultBundle']
                argv.remove('CODE_SIGNING_ALLOWED=NO')
                command['cwd'] = '/original/SwiftJLI/Examples/WatchQualification'
            elif command['name'] == 'compiler':
                command['argv'] = ['xcrun', 'swift', '--version']
            elif command['name'] == 'sdk':
                command['argv'] = ['xcrun', '--sdk', 'watchos', '--show-sdk-version']
            elif command['name'] == 'devices':
                command['argv'] = ['xcrun', 'xcdevice', 'list', '--timeout', '15']
        inventory = [{'identifier': report['device']['udid'], 'simulator': False,
                      'platform': 'com.apple.platform.watchos', 'available': True,
                      'architecture': 'arm64_32', 'modelCode': 'Watch99,99',
                      'modelName': 'MOCK Apple Watch', 'operatingSystemVersion': '26.5 (MOCKBUILD)'}]
        return report, copy.deepcopy(self.summary), self.log, inventory

    def test_genuine_simulator_capture_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'status|platform'):
            module.validate(self.report, self.summary, self.log, [])

    def test_capture_path_and_cwd_substitution_are_rejected(self):
        for change, message in [('cwd', 'cwd'), ('path', 'resultBundlePath'),
                                ('duplicate', 'resultBundlePath'), ('recorded', 'result bundle')]:
            with self.subTest(change=change):
                report, summary, log, inventory = self.negative_inputs()
                test = next(c for c in report['commands'] if c['name'] == 'test')
                if change == 'cwd':
                    test['cwd'] = '/other/Examples/WatchQualification'
                elif change == 'path':
                    test['argv'][test['argv'].index('-resultBundlePath') + 1] = '/other/Tests.xcresult'
                elif change == 'duplicate':
                    test['argv'] += ['-resultBundlePath', report['capturePaths']['resultBundle']]
                else:
                    report['capturePaths']['resultBundle'] = '/other/Tests.xcresult'
                with self.assertRaisesRegex(ValueError, message):
                    module.validate(report, summary, log, inventory)

    def test_capture_hashes_reject_substituted_bundle_and_logs(self):
        # Provenance helper only, using synthetic hashes and original paths
        # that do not exist here; relocation is permitted without hardware.
        report, _, _, _ = self.negative_inputs()
        hashes = {name: hashlib.sha256(('MOCK ' + name).encode()).hexdigest() for name in module.CAPTURE_FILES}
        bundle = {'Data/payload': hashlib.sha256(b'MOCK bundle').hexdigest()}
        report.update(captureSHA256=hashes, xcresultFilesSHA256=bundle)
        test = next(c for c in report['commands'] if c['name'] == 'test')
        test.update(stdout='test.log', stderr='test.stderr', stdoutSHA256=hashes['test.log'], stderrSHA256=hashes['test.stderr'])
        module.validate_capture_hashes(report, hashes, bundle)
        with self.assertRaisesRegex(ValueError, 'capture-time original bundle'):
            module.validate_capture_hashes(report, hashes, {'Data/payload': 'substituted'})
        for name in ['test.log', 'test.stderr', 'devices.json']:
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'capture-time hashes'):
                module.validate_capture_hashes(report, {**hashes, name: 'substituted'}, bundle)
        test['stderrSHA256'] = 'substituted'
        with self.assertRaisesRegex(ValueError, 'stderr'):
            module.validate_capture_hashes(report, hashes, bundle)

    def test_relabelled_report_cannot_make_simulator_xcresult_physical(self):
        report, summary, log, inventory = self.negative_inputs()
        with self.assertRaisesRegex(ValueError, 'xcresult must identify physical'):
            module.validate(report, summary, log, inventory)

    def test_negative_summary_and_command_controls(self):
        mutations = [
            ('command', lambda r,s,l,i: r['commands'][0].update(exit_code=1)),
            ('command', lambda r,s,l,i: r['commands'][0].update(timedOut=True)),
            ('result', lambda r,s,l,i: s.update(result='Failed')),
            ('skippedTests', lambda r,s,l,i: s.update(skippedTests=1)),
            ('expectedFailures', lambda r,s,l,i: s.update(expectedFailures=1)),
            ('passedTests', lambda r,s,l,i: s.update(passedTests=5)),
            ('configuration', lambda r,s,l,i: r.update(configuration='Debug')),
            ('Device test count', lambda r,s,l,i: s['devicesAndConfigurations'][0].update(skippedTests=1)),
        ]
        for name, mutate in mutations:
            with self.subTest(name=name):
                args = self.negative_inputs()
                mutate(*args)
                with self.assertRaisesRegex(ValueError, name):
                    module.validate(*args)

    def test_malformed_input_is_rejected(self):
        for inventory in [None, {}, [None]]:
            with self.subTest(inventory=inventory), self.assertRaises(ValueError):
                module.physical_device(inventory, 'MOCK')
        for log in ['WATCH_QUALIFICATION {broken', 'WATCH_QUALIFICATION null']:
            with self.subTest(log=log), self.assertRaises(ValueError):
                module.validate_records(log)
        with self.assertRaises(ValueError):
            module.validate(None, self.summary, self.log, [])

    def test_negative_hardware_identity_controls(self):
        for field, value in [('simulator', True), ('platform', 'com.apple.platform.iphonesimulator'),
                             ('available', False), ('architecture', 'x86_64'),
                             ('modelCode', 'iPhone99,99'), ('operatingSystemVersion', '25.0 (MOCK)')]:
            with self.subTest(field=field):
                report, _, _, inventory = self.negative_inputs()
                inventory[0][field] = value
                with self.assertRaises(ValueError):
                    module.physical_device(inventory, report['device']['udid'])

    def test_genuine_simulator_records_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'physical-watch'):
            module.validate_records(self.log)

    def test_synthetic_record_parser_only(self):
        # This positive parser unit has no hardware, summary, source or run.
        # It cannot and does not produce a successful qualification receipt.
        records = [{'case': name, 'environment': 'physical-watch', 'os': 'Version 26.5 (Build MOCK)',
                    'elapsedSeconds': 0.1, 'processPeakRSSBytes': 1, **module.shared.BUDGETS}
                   for name in sorted(module.shared.CASES)]
        serialise = lambda values: '\n'.join('WATCH_QUALIFICATION ' + json.dumps(v) for v in values)
        self.assertEqual(module.validate_records(serialise(records)), records)
        with self.assertRaisesRegex(ValueError, 'differs from hardware'):
            module.validate_records(serialise(records), '26.6', 'MOCK')
        with self.assertRaisesRegex(ValueError, 'differs from hardware'):
            module.validate_records(serialise(records), '26.5', 'OTHER')
        for field, value in [('environment', 'watch-simulator'), ('maximumWorkers', 3),
                             ('elapsedSeconds', float('nan')), ('processPeakRSSBytes', -1),
                             ('case', records[1]['case']), ('os', 'not a version')]:
            with self.subTest(field=field):
                changed = copy.deepcopy(records)
                changed[0][field] = value
                with self.assertRaises(ValueError):
                    module.validate_records(serialise(changed))

    def test_genuine_simulator_rejected_before_any_tool_query(self):
        with tempfile.TemporaryDirectory(prefix='watch-device-negative-') as scratch:
            evidence, output = Path(scratch) / 'input', Path(scratch) / 'output'
            evidence.mkdir()
            for filename in ['report.json', 'test.log', 'devices.json', 'xcode.log', 'compiler.log', 'sdk.log']:
                source = RETAINED / 'watch' / (filename if filename == 'report.json' else
                                              'devices.log.gz' if filename == 'devices.json' else filename + '.gz')
                data = source.read_bytes()
                (evidence / filename).write_bytes(gzip.decompress(data) if source.suffix == '.gz' else data)
            before = {x.name: x.read_bytes() for x in evidence.iterdir()}
            result = subprocess.run([sys.executable, '-B', str(HELPER), '--evidence', str(evidence), '--output', str(output)],
                                    capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            receipt = json.loads((output / 'receipt.json').read_text())
            self.assertEqual(receipt['status'], 'failed')
            self.assertIn('not physical', receipt['error'])
            self.assertEqual(receipt['commands'], [])
            self.assertEqual(before, {x.name: x.read_bytes() for x in evidence.iterdir()})
            existing = (output / 'receipt.json').read_bytes()
            result = subprocess.run([sys.executable, '-B', str(HELPER), '--evidence', str(evidence), '--output', str(output)],
                                    capture_output=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((output / 'receipt.json').read_bytes(), existing)

    def test_shared_preservation_helpers_reject_mutations(self):
        original = {'Data/payload': 'first'}
        with_cache = {**original, 'database.sqlite3': 'cache'}
        self.assertEqual(module.shared.validate_bundle_query(original, original, original, with_cache)['addedFiles'],
                         {'database.sqlite3': 'cache'})
        for after_original, after_copy in [(with_cache, with_cache), (original, {'Data/payload': 'changed'})]:
            with self.assertRaises(ValueError):
                module.shared.validate_bundle_query(original, after_original, original, after_copy)


if __name__ == '__main__':
    unittest.main(verbosity=2)
