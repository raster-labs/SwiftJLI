from pathlib import Path
import subprocess,json,hashlib
root=Path.cwd();binary=root/'work/build-apple-memory/release/AppleMemoryProbe';out=root/'work/evidence/apple-memory-qualified';out.mkdir(exist_ok=False)
repo=root/'work/SwiftJLI';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
record={'binarySHA256':sha(binary),'sourceHashes':{str(p.relative_to(repo)):sha(p) for p in [repo/'Package.swift',*sorted((repo/'Sources').rglob('*.swift')),*sorted((repo/'Examples/AppleMemoryProbe').rglob('*.swift'))]},'compiler':subprocess.check_output(['swift','--version'],text=True),'host':subprocess.check_output(['sw_vers'],text=True),'commands':[],'status':'running'}
for name,args in [('dct12',[]),('rgb8',['--rgb8'])]:
 for control in [False,True]:
  label=name+('-control' if control else '-baseline');cmd=[str(binary),*args,*(['--control-copy'] if control else [])]
  with (out/(label+'.jsonl')).open('w') as stdout,(out/(label+'.stderr')).open('w') as stderr:r=subprocess.run(cmd,stdout=stdout,stderr=stderr)
  record['commands'].append({'argv':cmd,'exitCode':r.returncode});(out/'results.json').write_text(json.dumps(record,indent=2)+'\n');assert r.returncode==0,label
  rows=[json.loads(s) for s in (out/(label+'.jsonl')).read_text().splitlines()];assert len(rows)==28 and all(x['profile']==name and x['controlCopy']==control for x in rows)
record['status']='passed';record['measurements']=56;record['controls']=56;record['logHashes']={p.name:sha(p) for p in out.glob('*.jsonl')};(out/'results.json').write_text(json.dumps(record,indent=2)+'\n');print('Apple memory: 56 measurements and 56 retained-copy controls passed')
