from pathlib import Path
import subprocess,json,hashlib
root=Path.cwd();out=root/'work/completion-evidence/attribution';binary=root/'work/completion-tiny-decode-attribution-build/out/Products/Release/Attribution';h=root/'work/completion-tiny-decode-attribution';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
meta={'purpose':'19x19 decoder attribution only; @testable code generation is not the public release baseline. No safety check is removed.','binarySHA256':sha(binary),'harnessHashes':{str(p.relative_to(h)):sha(p)for p in h.rglob('*.swift')},'commands':[],'status':'running'}
try:
 for n in [1,2]:
  log=out/f'tiny-decode-qualified-{n}.jsonl';err=out/f'tiny-decode-qualified-{n}.stderr'
  with log.open('w')as f,err.open('w')as e:r=subprocess.run([str(binary)],stdout=f,stderr=e,timeout=60)
  meta['commands'].append({'argv':[str(binary)],'exitCode':r.returncode,'stdoutSHA256':sha(log)})
  assert r.returncode==0
  rows=[json.loads(l)for l in log.read_text().splitlines()];assert len(rows)==5 and all(x['samplesEqual']and x['thermalState']==0 for x in rows)
 meta['status']='passed'
except BaseException as error:meta.update(status='failed',error=repr(error));raise
finally:(out/'tiny-results-qualified.json').write_text(json.dumps(meta,indent=2)+'\n')
print('Both five-profile tiny decoder diagnostics passed')
