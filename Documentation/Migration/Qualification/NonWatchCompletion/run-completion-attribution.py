# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
import subprocess,time,json,hashlib,datetime
root=Path.cwd();out=root/'work/completion-evidence/attribution';perf=root/'work/completion-evidence/performance/results.json'
while True:
 if perf.exists():
  status=json.loads(perf.read_text()).get('status','')
  if status=='failed':raise SystemExit('Public comparisons failed; diagnostics not started')
  if status.startswith('passed_'):break
 time.sleep(10)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
meta={'status':'running','predecessor':'981da4efb7d62e4370c5d6de706d56a729b9552e','commands':[],
 'purpose':'Diagnostic attribution only. @testable build code generation differs from public release timings; these durations are not additive acceptance measurements.',
 'sourceHashes':{str(p.relative_to(root/'work/SwiftJLI')):sha(p) for p in (root/'work/SwiftJLI/Sources').rglob('*.swift')}}
try:
 for repeat in [1,2]:
  for name in ['decode-attribution','rgb-encode-attribution','predictive-flat-attribution','dct12-final-attribution']:
   binary=root/'work'/('completion-'+name+'-build/out/Products/Release/Attribution')
   cmd=[str(binary)];label=f'{name}-{repeat}'
   with (out/(label+'.jsonl')).open('w') as stdout,(out/(label+'.stderr')).open('w') as stderr:
    result=subprocess.run(cmd,stdout=stdout,stderr=stderr,timeout=600)
   meta['commands'].append({'label':label,'argv':cmd,'exitCode':result.returncode,'binarySHA256':sha(binary),'stdoutSHA256':sha(out/(label+'.jsonl'))})
   (out/'results.json').write_text(json.dumps(meta,indent=2)+'\n')
   print(label,'exit',result.returncode,flush=True)
   if result.returncode:raise RuntimeError(label+' failed')
 meta['status']='passed_output_checks'
except BaseException as error:meta['status']='failed';meta['error']=repr(error);raise
finally:(out/'results.json').write_text(json.dumps(meta,indent=2)+'\n')
