#!/usr/bin/env python3
"""Run pinned, unchanged CLI checks/comparisons in a fresh evidence directory."""
import argparse
import datetime
import hashlib
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def snapshot(expected):
    return {path: sha(path) == value for path, value in expected.items()}


def host():
    return subprocess.check_output(['ps', '-axo', 'pid,pcpu,comm'], text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gate', choices=['cli-checks', 'benchmarks'], required=True)
    args = parser.parse_args()
    plan_path = ROOT / 'plan.json'
    plan = json.loads(plan_path.read_text())
    assert sha(__file__) == plan['runnerSHA256']
    assert plan['status'] == 'prepared-not-executed', plan.get('holdReason', 'Plan is not executable')
    gate = plan['gates'][args.gate]
    destination = pathlib.Path(gate['outputDirectory'])
    destination.mkdir(parents=True, exist_ok=False)
    receipt_path = destination / 'receipt.json'
    receipt = {'status': 'running', 'gate': args.gate, 'startedUTC': now(),
               'planSHA256': sha(plan_path), 'runnerSHA256': sha(__file__),
               'baselineRevision': plan['baselineRevision'],
               'candidateRevision': plan['candidateRevision'], 'commands': []}

    def save():
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')

    save()
    try:
        receipt['inputChecksBefore'] = snapshot(plan['inputSHA256'])
        assert all(receipt['inputChecksBefore'].values()), 'Input identity changed'
        repo = plan['sourceWorktree']
        receipt['sourceBefore'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
        receipt['sourceStatusBefore'] = subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo, text=True)
        assert receipt['sourceBefore'] == plan['candidateRevision'] and not receipt['sourceStatusBefore']
        receipt['hostBefore'] = host()
        save()
        for item in gate['commands']:
            output = pathlib.Path(item['output'])
            assert not output.exists(), 'Refusing to overwrite subprocess output'
            record = {'name': item['name'], 'command': item['command'], 'cwd': repo,
                      'startedUTC': now(), 'hostBefore': host()}
            receipt['commands'].append(record)
            save()
            stdout = destination / (item['name'] + '.stdout')
            stderr = destination / (item['name'] + '.stderr')
            with stdout.open('xb') as out, stderr.open('xb') as err:
                process = subprocess.run(item['command'], cwd=repo, stdout=out, stderr=err)
            record.update(exitCode=process.returncode, finishedUTC=now(), hostAfter=host(),
                          stdoutSHA256=sha(stdout), stderrSHA256=sha(stderr))
            save()
            assert process.returncode == 0, 'Subprocess failed; raw output retained'
            report = json.loads(output.read_text())
            assert report['status'] == 'passed'
            if args.gate == 'cli-checks':
                assert report['checks'] == 252
                assert report['binary_sha256'] == plan['binarySHA256']['candidate']
                assert report['test_runner_sha256'] == plan['inputSHA256'][plan['testScript']]
                record['checks'] = report['checks']
            else:
                assert report['binarySHA256'] == {**{k: plan['binarySHA256'][k] for k in ['baseline', 'candidate']},
                                                  'djpeg': plan['binarySHA256'][item['djpegVersion']]}
                assert report['arguments']['warmups'] == 5
                assert report['arguments']['iterations'] == 20
                assert report['arguments']['rounds'] == 2
                rows = report['records']
                exclusions = report['excluded']
                attempted = [(row['round'], row['profile'], row['size']) for row in rows + exclusions]
                expected = [tuple(row) for row in item['expectedAttemptedCases']]
                assert len(attempted) == len(expected) and set(attempted) == set(expected)
                assert len(rows) == item['expectedAcceptedRecords']
                assert len(exclusions) == item['expectedExcludedRecords']
                for row in rows + exclusions:
                    assert row['inputSHA256'] == plan['inputSHA256'][str(pathlib.Path(item['fixtures']) / f"{row['profile']}-{row['size']}.jpg")]
                    assert 'resourceRejections' not in row
                    assert row['validation']['baselineCandidateExactSamples']
                    assert row['validation']['baselineCandidateExactPNM']
                for row in rows:
                    for label in ['baseline', 'candidate', 'djpeg']:
                        assert len(row[label]['elapsedSeconds']['samples']) == 20
                        assert len(row[label]['peakRSSBytes']['samples']) == 20
                    assert row['validation']['maximumDjpegSampleDifference'] <= row['validation']['tolerance']
                for row in exclusions:
                    assert row['profile'] in ['rgb8', 'progressiveRGB8'] and row['size'] == 512
                    assert row['validation']['maximumDjpegSampleDifference'] == 3
                    assert row['validation']['tolerance'] == 2
                record.update(acceptedRecords=len(rows), excludedRecords=len(exclusions),
                              djpegVersion=report['djpegVersion'])
            record['outputSHA256'] = sha(output)
            record['inputChecksAfter'] = snapshot(plan['inputSHA256'])
            assert all(record['inputChecksAfter'].values()), 'Input identity changed during subprocess'
            assert sha(plan_path) == receipt['planSHA256']
            assert sha(__file__) == receipt['runnerSHA256']
            save()
            print(item['name'], 'passed', flush=True)
        receipt['inputChecksAfter'] = snapshot(plan['inputSHA256'])
        receipt['sourceAfter'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
        receipt['sourceStatusAfter'] = subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo, text=True)
        assert all(receipt['inputChecksAfter'].values())
        assert receipt['sourceAfter'] == receipt['sourceBefore'] and not receipt['sourceStatusAfter']
        assert sha(plan_path) == receipt['planSHA256'] and sha(__file__) == receipt['runnerSHA256']
        receipt.update(status='passed', finishedUTC=now(), hostAfter=host())
        save()
    except BaseException as error:
        receipt.update(status='failed', failure=repr(error), finishedUTC=now())
        save()
        raise


if __name__ == '__main__':
    main()
