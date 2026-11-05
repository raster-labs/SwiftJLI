import argparse, json, pathlib, re, statistics, subprocess

p = argparse.ArgumentParser()
p.add_argument('--candidate-products', required=True, type=pathlib.Path)
p.add_argument('--output', required=True, type=pathlib.Path)
p.add_argument('--kinds', nargs='+', default=['dct12', 'rgb8', 'progressiveRGB8'])
p.add_argument('--binary-prefix', default='/private/tmp/swiftjli-round4-dct-bounded')
a = p.parse_args()
products = {
    'baseline': pathlib.Path('/private/tmp/swiftjli-round3-parser-build/out/Products/Release'),
    'candidate': a.candidate_products,
}
root = pathlib.Path('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory')
records = []
for trial in range(3):
    for kind in a.kinds:
        for size in [512, 2048]:
            fixture = root / f'{kind}-{size}.jpg'
            for label in (['baseline', 'candidate'] if trial % 2 == 0 else ['candidate', 'baseline']):
                cmd = ['/usr/bin/time', '-l', a.binary_prefix + '-' + label, str(fixture)]
                result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=True)
                match = re.search(r'(\d+)\s+maximum resident set size', result.stderr)
                assert match, result.stderr
                records.append(dict(trial=trial+1, fixture=fixture.name, label=label, maximumRSSBytes=int(match[1]), command=cmd))
                a.output.write_text(json.dumps(records, indent=2) + '\n')
for fixture in sorted({r['fixture'] for r in records}):
    values = {label: statistics.median(r['maximumRSSBytes'] for r in records if r['fixture'] == fixture and r['label'] == label) for label in products}
    print(fixture, values, 'reductionPercent', round(100 * (1 - values['candidate']/values['baseline']), 2))
