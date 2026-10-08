from pathlib import Path
import subprocess,json,hashlib
root=Path.cwd();out=root/'work/evidence/final-performance';repo=root/'work/SwiftJLI';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
record={'sourceHashes':{str(p.relative_to(repo)):sha(p) for p in [repo/'Package.swift',*sorted((repo/'Sources').rglob('*.swift'))]},'commands':[],'harnesses':{},'status':'running'}
for name,product in [('dct12-final-attribution','Attribution'),('predictive-flat-attribution','Attribution'),('public-workers16','Benchmark')]:
 package=root/'work'/name;binary=root/'work'/('build-'+name)/'arm64-apple-macosx/release'/product
 record['harnesses'][name]={'binarySHA256':sha(binary),'sourceHashes':{str(p.relative_to(package)):sha(p) for p in package.rglob('*.swift') if '.build' not in p.parts}}
 for i in [1,2]:
  label=f'{name}-{i}';print('Starting',label,flush=True)
  with (out/(label+'.jsonl')).open('w') as stdout,(out/(label+'.stderr')).open('w') as stderr:r=subprocess.run([str(binary)],stdout=stdout,stderr=stderr,timeout=300)
  record['commands'].append({'name':label,'argv':[str(binary)],'exitCode':r.returncode});(out/'additional-attribution-results.json').write_text(json.dumps(record,indent=2)+'\n');assert r.returncode==0,label
record['status']='passed';(out/'additional-attribution-results.json').write_text(json.dumps(record,indent=2)+'\n');print('Additional attributions completed',flush=True)
