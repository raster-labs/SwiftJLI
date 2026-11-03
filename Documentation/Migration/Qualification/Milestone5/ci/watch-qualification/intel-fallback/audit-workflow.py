#!/usr/bin/env python3
"""Read-only structural audit; does not execute GitHub Actions or codec tests."""
import argparse
import copy
import datetime
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

PARSER = r'''
require 'psych'
require 'json'
text = STDIN.read
def inspect_node(node)
  if node.is_a?(Psych::Nodes::Mapping)
    keys = node.children.each_slice(2).map { |pair| pair[0].value }
    raise 'Duplicate YAML mapping key' unless keys.uniq == keys
  end
  raise 'Unexpected YAML alias' if node.is_a?(Psych::Nodes::Alias)
  (node.children || []).each { |child| inspect_node(child) }
end
inspect_node(Psych.parse_stream(text))
value = Psych.load(text)
# Psych 3 uses YAML 1.1 and parses the Actions top-level 'on' key as true.
value['on'] = value.delete(true) if value.key?(true)
puts JSON.generate({'document' => value, 'ruby' => RUBY_VERSION, 'psych' => Psych::VERSION})
'''
SKIP = "github.event_name != 'workflow_dispatch'"
PLATFORMS = '${{ github.event_name == \'workflow_dispatch\' && fromJSON(\'["watchOS"]\') || fromJSON(\'["tvOS", "visionOS", "watchOS"]\') }}'
RUNNER = "${{ github.event_name == 'workflow_dispatch' && 'macos-26-intel' || 'macos-26' }}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, required=True)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output already exists; retain previous audit receipts')
    commands = []

    def run(argv, data=None):
        result = subprocess.run(argv, cwd=args.repository, input=data,
                                capture_output=True, timeout=30)
        commands.append({'argv': argv, 'exitCode': result.returncode,
                         'stdoutSHA256': hashlib.sha256(result.stdout).hexdigest(),
                         'stderr': result.stderr.decode()})
        result.check_returncode()
        return result.stdout

    path = '.github/workflows/contract.yml'
    old_bytes = run(['git', 'show', args.baseline + ':' + path])
    new_bytes = (args.repository / path).read_bytes()
    old_parse = json.loads(run(['ruby', '-e', PARSER], old_bytes))
    new_parse = json.loads(run(['ruby', '-e', PARSER], new_bytes))
    old = old_parse['document']
    new = new_parse['document']
    normal = copy.deepcopy(new)
    assert 'workflow_dispatch' not in old['on']
    assert 'workflow_dispatch' in normal['on'] and normal['on']['workflow_dispatch'] is None
    del normal['on']['workflow_dispatch']
    assert set(old['jobs']) == set(new['jobs']) and len(new['jobs']) == 8
    skipped = []
    for name, job in normal['jobs'].items():
        if name != 'other-apple-simulators':
            assert 'if' not in old['jobs'][name]
            assert job.pop('if') == SKIP
            skipped.append(name)
    watch = normal['jobs']['other-apple-simulators']
    assert watch['strategy']['matrix']['platform'] == PLATFORMS
    assert watch['runs-on'] == RUNNER
    watch['strategy']['matrix']['platform'] = ['tvOS', 'visionOS', 'watchOS']
    watch['runs-on'] = 'macos-26'
    assert normal == old, 'Unexpected normal-event change in parsed workflow'
    assert new['jobs']['other-apple-simulators']['steps'] == old['jobs']['other-apple-simulators']['steps']
    normal_counts = {name: math.prod(len(values) for values in job.get('strategy', {}).get('matrix', {}).values())
                     for name, job in normal['jobs'].items()}
    assert sum(normal_counts.values()) == 13 and len(skipped) == 7
    run(['git', 'diff', '--check', '--', path])
    receipt = {
        'auditedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'status': 'passed', 'baselineRevision': args.baseline,
        'checkoutRevision': run(['git', 'rev-parse', 'HEAD']).decode().strip(),
        'workflow': path,
        'baselineSHA256': hashlib.sha256(old_bytes).hexdigest(),
        'auditedSHA256': hashlib.sha256(new_bytes).hexdigest(),
        'helperSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'parser': {'ruby': new_parse['ruby'], 'psych': new_parse['psych'],
                   'duplicateKeysRejected': True, 'aliasesRejected': True,
                   'yaml11OnKeyNormalised': True},
        'normalEvents': {'events': ['pull_request', 'push'], 'deepEqualToBaselineAfterEvaluatingAddedConditions': True,
                         'jobCounts': normal_counts, 'totalJobs': 13},
        'manualDispatch': {'executedJobDefinitions': ['other-apple-simulators'], 'platforms': ['watchOS'],
                           'runner': 'macos-26-intel', 'totalJobs': 1, 'skippedJobDefinitions': skipped,
                           'allTargetJobStepsUnchanged': True, 'includesLibrarySuiteAndSixReleaseCaseVerifier': True},
        'unchanged': ['normal event triggers', 'permissions', 'concurrency', 'timeouts', 'all job steps',
                      'action pins', 'failure propagation', 'always-upload evidence paths and retention'],
        'method': 'Ruby Psych parse and duplicate-key check; exact expression-string checks; evaluate the two explicit event branches, then recursively compare the complete normal-event structure. This is not a GitHub Actions expression-engine execution.',
        'limits': ['No workflow dispatch, hosted run, codec build/test or simulator execution.',
                   'Runner allocation and successful execution remain unverified by this static audit.',
                   'Manual Watch success would not qualify skipped jobs, physical devices or performance.'],
        'invocation': [sys.executable, *sys.argv], 'commands': commands,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream:
        json.dump(receipt, stream, indent=2)
        stream.write('\n')
    print(json.dumps({'status': 'passed', 'normalJobs': 13, 'manualJobs': 1,
                      'workflowSHA256': receipt['auditedSHA256']}))


if __name__ == '__main__':
    main()
