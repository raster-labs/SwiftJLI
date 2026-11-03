#!/usr/bin/env python3
"""Recompute retained CLI samples; preserve matrices and exclusions separately."""
import datetime
import hashlib
import json
import pathlib
import statistics

ROOT = pathlib.Path(__file__).resolve().parent
plan_path = ROOT / 'plan.json'
plan = json.loads(plan_path.read_text())
output = ROOT.parent / 'cli-benchmark-1'
receipt_path = output / 'receipt.json'
receipt = json.loads(receipt_path.read_text())
sha = lambda path: hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
assert receipt['status'] == 'passed'
assert receipt['planSHA256'] == sha(plan_path)
assert all(receipt['inputChecksBefore'].values()) and all(receipt['inputChecksAfter'].values())
assert all(sha(path) == value for path, value in plan['inputSHA256'].items())
summary = {'sourceRevision': plan['candidateRevision'], 'baselineRevision': plan['baselineRevision'],
           'planSHA256': sha(plan_path), 'receiptSHA256': sha(receipt_path),
           'analysisSHA256': sha(__file__), 'createdUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
           'method': plan['method'], 'qualityScope': plan['qualityScope'],
           'percentageConvention': '100*(candidate/comparator-1); negative means lower candidate elapsed time or RSS.',
           'matrices': []}
for command in receipt['commands']:
    path = output / (command['name'] + '.json')
    assert sha(path) == command['outputSHA256']
    raw = json.loads(path.read_text())
    assert raw['status'] == 'passed' and all(command['inputChecksAfter'].values())
    matrix = {'name': command['name'], 'rawSHA256': sha(path), 'djpegVersion': raw['djpegVersion'],
              'acceptedRecords': len(raw['records']), 'excludedRecords': len(raw['excluded']),
              'exclusions': raw['excluded'], 'records': [], 'cases': []}
    grouped = {}
    for row in raw['records']:
        for label in ['baseline', 'candidate', 'djpeg']:
            for metric in ['elapsedSeconds', 'peakRSSBytes']:
                values = row[label][metric]['samples']
                assert len(values) == 20
                assert row[label][metric]['median'] == statistics.median(values)
                assert row[label][metric]['p95'] == sorted(values)[18]
        medians = {label: row[label]['elapsedSeconds']['median'] for label in ['baseline', 'candidate', 'djpeg']}
        rss = {label: row[label]['peakRSSBytes']['median'] for label in ['baseline', 'candidate', 'djpeg']}
        record = {'round': row['round'], 'profile': row['profile'], 'size': row['size'],
                  'medianMilliseconds': {label: value * 1000 for label, value in medians.items()},
                  'medianPeakRSSBytes': rss,
                  'elapsedVsBaselinePercent': (medians['candidate'] / medians['baseline'] - 1) * 100,
                  'elapsedVsDjpegPercent': (medians['candidate'] / medians['djpeg'] - 1) * 100,
                  'rssVsBaselinePercent': (rss['candidate'] / rss['baseline'] - 1) * 100,
                  'rssVsDjpegPercent': (rss['candidate'] / rss['djpeg'] - 1) * 100,
                  'validation': row['validation']}
        matrix['records'].append(record)
        grouped.setdefault((row['profile'], row['size']), []).append(record)
    for (profile, size), rows in grouped.items():
        assert len(rows) == 2 and {row['round'] for row in rows} == {1, 2}
        rows.sort(key=lambda row: row['round'])
        matrix['cases'].append({'profile': profile, 'size': size,
            'elapsedVsBaselinePercent': [row['elapsedVsBaselinePercent'] for row in rows],
            'elapsedVsDjpegPercent': [row['elapsedVsDjpegPercent'] for row in rows],
            'candidateBeatsDjpegBothRounds': all(row['elapsedVsDjpegPercent'] < 0 for row in rows),
            'candidateBeatsBaselineBothRounds': all(row['elapsedVsBaselinePercent'] < 0 for row in rows),
            'candidateSlowerThanBaselineOver5PercentBothRounds': all(row['elapsedVsBaselinePercent'] > 5 for row in rows)})
    matrix['candidateBeatsDjpegCasesBothRounds'] = sum(row['candidateBeatsDjpegBothRounds'] for row in matrix['cases'])
    matrix['candidateBeatsBaselineCasesBothRounds'] = sum(row['candidateBeatsBaselineBothRounds'] for row in matrix['cases'])
    matrix['repeatedBaselineOver5PercentCases'] = [row for row in matrix['cases'] if row['candidateSlowerThanBaselineOver5PercentBothRounds']]
    summary['matrices'].append(matrix)
destination = output / 'summary.json'
with destination.open('x') as stream:
    json.dump(summary, stream, indent=2)
    stream.write('\n')
for matrix in summary['matrices']:
    print(matrix['name'], 'records', matrix['acceptedRecords'], 'excluded', matrix['excludedRecords'],
          'djpeg wins both rounds', matrix['candidateBeatsDjpegCasesBothRounds'], '/', len(matrix['cases']),
          'repeated baseline >5%', [(row['profile'], row['size']) for row in matrix['repeatedBaselineOver5PercentCases']])
