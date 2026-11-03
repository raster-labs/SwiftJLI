import datetime
import hashlib
import json
import pathlib
import re
import statistics
import subprocess
import time

root = pathlib.Path(__file__).parent
paths = {
    'baseline': pathlib.Path('/private/tmp/swiftjli-round4-build/out/Products/Release/swiftjli-cli'),
    'candidate': pathlib.Path('/private/tmp/swiftjli-round5-cli-build/out/Products/Release/swiftjli-cli'),
}
fixtures = [pathlib.Path('/private/tmp/swiftjli-native-matrix-fixtures') / f'{pattern}-{size}.jpg'
            for pattern in ['flat', 'ramp', 'noise', 'mixed'] for size in [19, 512]]
fixtures.append(pathlib.Path('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory/dct12-512.jpg'))
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
rss_pattern = re.compile(rb'\n\s*(\d+)\s+maximum resident set size')
def host_load():
    rows = []
    for line in subprocess.check_output(['ps', '-axo', 'pid,pcpu,comm'], text=True).splitlines()[1:]:
        parts = line.split(None, 2)
        if len(parts) == 3 and float(parts[1]) >= 10:
            rows.append({'pid': int(parts[0]), 'cpuPercent': float(parts[1]), 'process': parts[2]})
    return rows

result = {
    'status': 'running', 'startedUTC': now(),
    'method': 'Normal release CLI builds; unchanged source except macOS release executable-only linker settings. Fresh process per observation; five warmups and twenty timed observations per binary/case/round. Two rounds with alternating paired binary order. Wall time includes Darwin time-l wrapper, launch, read, decode, PNM output to /dev/null and exit. Full PNM bytes must match before each round. No dropped samples or relaxed quality thresholds.',
    'baselineRevision': 'bbb0b1a9a602807643fc254fb4e0d54a162d5ae8',
    'baselineSourceNote': 'Production sources identical to prior qualified 0a8acd7; baseline products are from round4 final build.',
    'candidateRevision': 'bbb0b1a9a602807643fc254fb4e0d54a162d5ae8 plus recorded Package.swift patch',
    'binarySHA256': {label: sha(path) for label, path in paths.items()},
    'manifestSHA256': sha(pathlib.Path('/private/tmp/swiftjli-round5-cli/Package.swift')),
    'fixtureSHA256': {p.name: sha(p) for p in fixtures},
    'powerBefore': subprocess.check_output(['pmset', '-g', 'batt'], text=True),
    'hostLoadBefore': host_load(), 'records': [],
}
def save():
    (root / 'benchmark.json').write_text(json.dumps(result, indent=2) + '\n')
def summary(samples):
    return {'samples': samples, 'median': statistics.median(samples),
            'p95': sorted(samples)[18], 'minimum': min(samples), 'maximum': max(samples)}
save()
for round_number in [1, 2]:
    for fixture in fixtures:
        commands = {label: [str(path), 'decode', '-i', str(fixture), '-o', '-', '--output-format', 'pnm']
                    for label, path in paths.items()}
        outputs = {label: subprocess.run(command, check=True, stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, timeout=30).stdout for label, command in commands.items()}
        assert outputs['baseline'] == outputs['candidate'], fixture.name + ': output mismatch'
        row = {'round': round_number, 'fixture': fixture.name, 'commands': commands,
               'baselineCandidateExactPNM': True, 'outputSHA256': hashlib.sha256(outputs['candidate']).hexdigest(),
               'outputBytes': len(outputs['candidate']), 'hostLoadBefore': host_load()}
        elapsed = {label: [] for label in paths}
        rss = {label: [] for label in paths}
        for iteration in range(25):
            order = ['baseline', 'candidate'] if (iteration + round_number) % 2 else ['candidate', 'baseline']
            for label in order:
                started = time.perf_counter_ns()
                run = subprocess.run(['/usr/bin/time', '-l'] + commands[label], check=True,
                      stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=30)
                seconds = (time.perf_counter_ns() - started) / 1e9
                match = rss_pattern.search(run.stderr)
                assert match, repr(run.stderr)
                if iteration >= 5:
                    elapsed[label].append(seconds)
                    rss[label].append(int(match[1]))
        for label in paths:
            row[label] = {'elapsedSeconds': summary(elapsed[label]), 'peakRSSBytes': summary(rss[label])}
        result['records'].append(row)
        save()
        print(round_number, fixture.name, *(f'{k}={row[k]["elapsedSeconds"]["median"]*1000:.3f}ms/{row[k]["peakRSSBytes"]["median"]/1048576:.3f}MiB' for k in paths), flush=True)
for label, path in paths.items():
    assert sha(path) == result['binarySHA256'][label]
result.update(status='passed', finishedUTC=now(), hostLoadAfter=host_load(),
              powerAfter=subprocess.check_output(['pmset', '-g', 'batt'], text=True))
save()
