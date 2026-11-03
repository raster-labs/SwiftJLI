import hashlib, json, pathlib, re, subprocess, datetime
root = pathlib.Path(__file__).parent
binaries = {'baseline': pathlib.Path('/private/tmp/swiftjli-round5-evidence/pipeline/owned-output/compare'),
            'candidate': root / 'compare'}
coverage = pathlib.Path('/private/tmp/swiftjli-round2-dct-coverage')
cases = [(coverage / f'flat-{bits}-512.jpg', 2 if bits == 8 else 4) for bits in [8,12]]
cases.append((pathlib.Path('/private/tmp/swiftjli-native-matrix-fixtures/flat-19.jpg'),0))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
result = {'method': 'Provisional compact DC diagnostic. Same retained harness and libjpeg3.2.1 archive in both binaries. Timing includes owned output; five warmups/twenty samples/two balanced rounds. Three fresh processes per binary/engine/case for peak RSS, retained full output. Fixed tolerances0/2/4. No concurrent local builds/tests.',
          'baselineRevision': '704ddae1bafea95d8a48c01ce35887c5b6413c0d',
          'candidateRevision': 'bd890f20b479ab3b207d77923cb56cd5b70eca0f',
          'binarySHA256': {k:sha(v) for k,v in binaries.items()},
          'fixtures': {str(p):sha(p) for p,_ in cases},
          'commands': [], 'timing': [], 'memory': []}
def save(): (root/'paired-compact.json').write_text(json.dumps(result,indent=2)+'\n')
def run(cmd):
    entry={'command':list(map(str,cmd)),'startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    result['commands'].append(entry);save()
    p=subprocess.run(cmd,capture_output=True,timeout=90)
    entry['exitCode']=p.returncode
    if p.returncode: entry.update(stdout=p.stdout.decode(errors='replace'),stderr=p.stderr.decode(errors='replace'))
    save();p.check_returncode();return p
for trial in [1,2]:
    for fixture,tolerance in cases:
        pair={}
        for label in (['baseline','candidate'] if trial==1 else ['candidate','baseline']):
            p=run([str(binaries[label]),'timing',str(fixture),'8',str(tolerance),str(trial)])
            item=json.loads(p.stdout);assert item['status']=='passed',item
            pair[label]=item;result['timing'].append(dict(label=label,trial=trial,**item));save()
        assert pair['baseline']['swiftFNV1a64']==pair['candidate']['swiftFNV1a64']
for trial in [1,2,3]:
    for fixture,tolerance in cases:
        for label in (['baseline','candidate'] if trial%2 else ['candidate','baseline']):
            for engine in (['swift','turbo'] if trial%2 else ['turbo','swift']):
                p=run(['/usr/bin/time','-l',str(binaries[label]),'memory-'+engine,str(fixture),'8',str(tolerance),str(trial)])
                item=json.loads(p.stdout)
                match=re.search(rb'\n\s*(\d+)\s+maximum resident set size',p.stderr);assert match,p.stderr
                result['memory'].append(dict(label=label,trial=trial,maximumRSSBytes=int(match[1]),**item));save()
assert {k:sha(v) for k,v in binaries.items()}==result['binarySHA256']
result['status']='passed';save();print('All compact timing/quality and fresh full-output RSS trials passed.')
