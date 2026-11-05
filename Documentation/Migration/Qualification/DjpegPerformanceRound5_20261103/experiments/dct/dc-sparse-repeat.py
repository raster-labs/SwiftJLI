import hashlib, json, pathlib, subprocess
root = pathlib.Path('/private/tmp/swiftjli-round5-dct-evidence')
fixtures = pathlib.Path('/private/tmp/swiftjli-round5-dct-fixtures')
records = []
for trial in range(5):
    for bits in [8, 12]:
        fixture = fixtures/f'late-ac-{bits}-512.jpg'
        pair = {}
        for label in (['baseline', 'candidate'] if trial%2==0 else ['candidate', 'baseline']):
            binary = root/('dc-candidate-native-'+label)
            row = json.loads(subprocess.check_output([str(binary), str(fixture)],text=True))
            records.append(dict(round=trial+1, label=label, **row));pair[label]=row
        assert pair['baseline']['outputSHA256'] == pair['candidate']['outputSHA256']
        ratio = pair['candidate']['medianSeconds']/pair['baseline']['medianSeconds']
        print(fixture.name,trial+1,{label:round(row['medianSeconds']*1000,4) for label,row in pair.items()},f'ratio={ratio:.4f}',flush=True)
        (root/'dc-sparse-repeat.json').write_text(json.dumps(dict(
            status='Provisional timings under continuing host contention',
            baseline='ab59b206ccac3c1c2c993d40b04a2a010c98eb60',
            binarySHA256={label:hashlib.sha256((root/('dc-candidate-native-'+label)).read_bytes()).hexdigest()
                          for label in ['baseline','candidate']},records=records),indent=2)+'\n')
