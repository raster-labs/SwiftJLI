import datetime
import hashlib
import json
import pathlib
import re
import subprocess

root = pathlib.Path(__file__).parent
binary = root / 'compare'
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
def host_load():
    rows = []
    for line in subprocess.check_output(['ps', '-axo', 'pid,pcpu,comm'], text=True).splitlines()[1:]:
        values = line.split(None, 2)
        if len(values) == 3 and float(values[1]) >= 10:
            rows.append({'pid': int(values[0]), 'cpuPercent': float(values[1]), 'process': values[2]})
    return rows
patterns = pathlib.Path('/private/tmp/swiftjli-native-matrix-fixtures')
dct = pathlib.Path('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory')
coverage = pathlib.Path('/private/tmp/swiftjli-round2-dct-coverage')
cases = [(patterns / (pattern + '-19.jpg'), 8, 0) for pattern in ['flat', 'ramp', 'noise', 'mixed']]
cases += [(patterns / 'mixed-2048.jpg', 8, 0)]
cases += [(dct / f'dct12-{size}.jpg', 8, 4) for size in [512, 2048]]
cases += [(dct / 'dct12-2048.jpg', 1, 4)]
cases += [(coverage / f'{pattern}-{bits}-512.jpg', 8, 2 if bits == 8 else 4)
          for pattern in ['flat', 'noise'] for bits in [8, 12]]
cases += [(dct / f'{profile}-{size}.jpg', 8, 2)
          for profile in ['rgb8', 'progressiveRGB8'] for size in [512, 2048]]
result = {'status': 'running', 'startedUTC': now(), 'binarySHA256': sha(binary),
          'method': 'Diagnostic allocated-output API comparison, not a replacement for CLI results. Both decoder paths use the same Swift executable and linked runtime images. Compressed Data is retained. Timings include decoder state/workspace and calloc/owned output allocation through finish/return; complete output retained until checks outside timing, then released outside timing. Five warmups,20 individual samples per engine,2 paired order-balanced rounds. Full per-sample quality gate before timing. RSS uses separate fresh processes with compressed input plus one full output retained;3 paired trials. Explicit Swift workspace8GiB/total10GiB,libjpeg fixture output limit512MiB/dimension8192, no disk output or decoded output copy.',
          'fixtureSHA256': {str(path): sha(path) for path, _, _ in cases},
          'records': [], 'excluded': [], 'memory': [], 'commands': [],
          'hostLoadBefore': host_load(), 'powerBefore': subprocess.check_output(['pmset', '-g', 'batt'], text=True)}
def save():
    (root / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
def run(command):
    entry = {'command': command, 'startedUTC': now()}
    result['commands'].append(entry)
    save()
    process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
    entry.update(exitCode=process.returncode, finishedUTC=now())
    if process.returncode:
        entry.update(stdout=process.stdout.decode(errors='replace'), stderr=process.stderr.decode(errors='replace'))
        save()
        raise RuntimeError(str(entry))
    return process
save()
errors = run([str(binary), 'errors', str(patterns / 'flat-19.jpg'), '8', '0', '1'])
result['containedErrorCheck'] = json.loads(errors.stdout)
accepted = {}
for round_number in [1, 2]:
    for fixture, workers, tolerance in cases:
        process = run([str(binary), 'timing', str(fixture), str(workers), str(tolerance), str(round_number)])
        record = json.loads(process.stdout)
        record['hostLoadAfter'] = host_load()
        if record['status'] == 'quality-excluded':
            result['excluded'].append(record)
        else:
            result['records'].append(record)
            accepted[str(fixture), workers, tolerance] = record
        save()
        print(round_number, fixture.name, workers, record['status'], record['maximumSampleDifference'],
              *(f'{name}={record[name]["medianSeconds"]*1000:.4f}ms' for name in ['swift', 'turbo'] if name in record), flush=True)
rss_pattern = re.compile(rb'\n\s*(\d+)\s+maximum resident set size')
for (fixture, workers, tolerance) in accepted:
    assert sum(record['fixture'] == pathlib.Path(fixture).name and record['workerCeiling'] == workers
               for record in result['records']) == 2, 'Quality disposition changed between rounds'
for trial in [1, 2, 3]:
    for (fixture, workers, tolerance), quality in accepted.items():
        for engine in (['swift', 'turbo'] if trial % 2 else ['turbo', 'swift']):
            process = run(['/usr/bin/time', '-l', str(binary), 'memory-' + engine,
                           fixture, str(workers), str(tolerance), str(trial)])
            memory = json.loads(process.stdout)
            match = rss_pattern.search(process.stderr)
            assert match, repr(process.stderr)
            assert memory['outputBytes'] == quality['outputBytes']
            assert memory['outputFNV1a64'] == quality[engine + 'FNV1a64']
            memory.update(trial=trial, maximumRSSBytes=int(match[1]))
            result['memory'].append(memory)
            save()
assert sha(binary) == result['binarySHA256']
result.update(status='passed', finishedUTC=now(), hostLoadAfter=host_load(),
              powerAfter=subprocess.check_output(['pmset', '-g', 'batt'], text=True))
save()
print('Completed all fixed-quality gates, timing rounds and fresh full-output RSS trials.', flush=True)
