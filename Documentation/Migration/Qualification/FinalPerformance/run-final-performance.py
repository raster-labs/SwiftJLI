import json,time,subprocess,pathlib,hashlib
root=pathlib.Path.cwd();campaign=root/'work/evidence/final-0a714f3-fuzz/campaign.json'
while True:
 s=json.loads(campaign.read_text())
 if s.get('status')=='passed':break
 if s.get('status')=='failed':raise SystemExit('Fuzz failed; performance not started')
 time.sleep(10)
repo=root/'work/SwiftJLI';out=root/'work/evidence/final-performance';out.mkdir(exist_ok=False)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
record={'sourceHashes':{str(p.relative_to(repo)):sha(p) for p in [repo/'Package.swift',*sorted((repo/'Sources').rglob('*.swift'))]},'status':'running','commands':[]}
for p,h in s['source_hashes'].items():
 if p in record['sourceHashes'] and record['sourceHashes'][p]!=h:raise SystemExit('Shipping source changed: '+p)
public=root/'work/build-benchmark-fused-u12/arm64-apple-macosx/release/Benchmark'
attribution=root/'work/build-decode-attribution-final/arm64-apple-macosx/release/Attribution'
for name,binary,args in [('decode-attribution-1',attribution,[]),('decode-attribution-2',attribution,[]),('public-extended-1',public,['--extended']),('public-extended-2',public,['--extended'])]:
 print('Starting '+name,flush=True)
 command=['/usr/bin/caffeinate','-i',str(binary),*args]
 with (out/(name+'.jsonl')).open('w') as stdout,(out/(name+'.stderr')).open('w') as stderr:
  result=subprocess.run(command,stdout=stdout,stderr=stderr,timeout=900)
 record['commands'].append({'name':name,'argv':command,'binarySHA256':sha(binary),'exitCode':result.returncode,'stdoutSHA256':sha(out/(name+'.jsonl'))})
 (out/'results.json').write_text(json.dumps(record,indent=2)+'\n')
 if result.returncode:raise SystemExit(result.returncode)
record['status']='passed';(out/'results.json').write_text(json.dumps(record,indent=2)+'\n');print('Performance runs completed',flush=True)
