#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run the library suite on an installed OS 26+ simulator; never substitute a build."""
import argparse
import json
import re
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = {'platform': 'iOS Simulator', 'commands': [], 'status': 'running'}

    def save():
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(name, command, timeout=120):
        print('Running: ' + ' '.join(command), flush=True)
        result = subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=timeout)
        (out / (name + '.log')).write_text(result.stdout + result.stderr)
        report['commands'].append({'name': name, 'argv': command, 'exit_code': result.returncode})
        save()
        if result.returncode:
            print((result.stdout + result.stderr)[-20000:], flush=True)
            raise RuntimeError(f'{name} failed with exit {result.returncode}')
        return result.stdout

    try:
        report['revision'] = run('revision', ['git', 'rev-parse', 'HEAD']).strip()
        report['xcode'] = run('xcode', ['xcodebuild', '-version']).strip()
        report['compiler'] = run('compiler', ['swift', '--version']).strip()
        report['sdk'] = run('sdk', ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version']).strip()
        devices = json.loads(run('devices', ['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))
        candidates = []
        for runtime, values in devices['devices'].items():
            match = re.search(r'SimRuntime\.iOS-(\d+)(?:-(\d+))?', runtime)
            if match and int(match[1]) >= 26:
                for device in values:
                    if device.get('isAvailable') and device['name'].startswith('iPhone'):
                        candidates.append(((int(match[1]), int(match[2] or 0)), runtime, device))
        if not candidates:
            raise RuntimeError('No installed OS 26+ iPhone simulator: runtime gate is unexecuted')
        _, runtime, device = sorted(candidates, key=lambda c: (c[0], c[2]['name']))[-1]
        report.update(runtime=runtime, device=device)
        schemes = json.loads(run('schemes', ['xcodebuild', '-list', '-json']))
        names = [name for container in schemes.values() if isinstance(container, dict)
                 for name in container.get('schemes', [])]
        # Xcode's library product scheme has no test action; the generated
        # package scheme includes SwiftJLITests.
        scheme = next((name for name in ['SwiftJLI-Package', 'SwiftJLI'] if name in names), None)
        if scheme is None:
            raise RuntimeError(f'Library test scheme missing: {names}')
        report['scheme'] = scheme
        log = run('test', ['xcodebuild', 'test', '-scheme', scheme,
            '-destination', 'platform=iOS Simulator,id=' + device['udid'],
            '-destination-timeout', '120', '-parallel-testing-enabled', 'NO',
            '-derivedDataPath', str(out / 'DerivedData'),
            '-resultBundlePath', str(out / 'Tests.xcresult'), 'CODE_SIGNING_ALLOWED=NO'], timeout=1500)
        # A build-only or zero-test success is not runtime qualification.
        counts = re.findall(r'Test run with (\d+) tests?(?: in \d+ suites?)? passed', log)
        if not counts or max(map(int, counts)) == 0:
            raise RuntimeError('No successful Swift Testing run count in xcodebuild output; inspect xcresult')
        report['testsPassed'] = max(map(int, counts))
        report['status'] = 'passed'
        save()
        print(f'iOS simulator passed: {report["testsPassed"]} tests on {device["name"]}, {runtime}')
    except Exception as error:
        report.update(status='failed', error=str(error))
        save()
        raise


if __name__ == '__main__':
    main()
