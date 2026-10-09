import time,json,pathlib,subprocess,hashlib
r=pathlib.Path.cwd();target=r/'work/evidence/final-performance/results.json'
while not target.exists() or json.loads(target.read_text()).get('status')!='passed':time.sleep(10)
b=r/'work/build-rgb-encode-attribution/arm64-apple-macosx/release/Attribution';o=r/'work/evidence/final-performance';record={'binarySHA256':hashlib.sha256(b.read_bytes()).hexdigest(),'harnessHashes':{str(p.relative_to(r/'work/rgb-encode-attribution')):hashlib.sha256(p.read_bytes()).hexdigest() for p in (r/'work/rgb-encode-attribution').rglob('*.swift') if '.build' not in p.parts},'commands':[]}
for i in [1,2]:
 with (o/f'rgb-encode-attribution-{i}.jsonl').open('w') as stdout,(o/f'rgb-encode-attribution-{i}.stderr').open('w') as stderr:result=subprocess.run(['/usr/bin/caffeinate','-i',str(b)],stdout=stdout,stderr=stderr,timeout=300)
 record['commands'].append({'iteration':i,'exitCode':result.returncode});assert result.returncode==0
record['status']='passed';(o/'rgb-encode-attribution-sources.json').write_text(json.dumps(record,indent=2)+'\n');print('RGB encoder attribution completed',flush=True)
