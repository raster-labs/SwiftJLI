import argparse, hashlib, json, pathlib, subprocess
p = argparse.ArgumentParser()
p.add_argument('--baseline', required=True)
p.add_argument('--candidate', required=True)
p.add_argument('--output', required=True, type=pathlib.Path)
a = p.parse_args()
root = pathlib.Path('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory')
extra = pathlib.Path('/private/tmp/swiftjli-round2-dct-coverage')
fixtures = [root / f'dct12-{size}.jpg' for size in [512, 2048]]
fixtures += [extra / f'{kind}-{bits}-512.jpg' for kind in ['flat', 'noise'] for bits in [8, 12]]
records = []
binary_hashes = {label: hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest() for label,path in [('baseline',a.baseline),('candidate',a.candidate)]}
for trial in range(3):
    for fixture in fixtures:
        pair = {}
        for label, binary in ([('baseline', a.baseline), ('candidate', a.candidate)] if trial % 2 == 0 else [('candidate', a.candidate), ('baseline', a.baseline)]):
            value = json.loads(subprocess.check_output([binary, str(fixture)], text=True))
            records.append(dict(round=trial+1,label=label,**value));pair[label]=value
        assert pair['baseline']['outputSHA256'] == pair['candidate']['outputSHA256']
        assert pair['baseline']['outputBytes'] == pair['candidate']['outputBytes']
        a.output.write_text(json.dumps(dict(binarySHA256=binary_hashes, records=records),indent=2)+'\n')
        print(fixture.name,trial+1,{label:round(value['medianSeconds']*1000,3) for label,value in pair.items()},flush=True)
