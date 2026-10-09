from pathlib import Path
import subprocess,json,hashlib
root=Path.cwd();out=root/'work/evidence/isolated-memory-controls';out.mkdir(exist_ok=False);binary=root/'work/build-isolated-memory-control/arm64-apple-macosx/release/Memory';rows=[];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
meta={'binarySHA256':sha(binary),'harnessHashes':{str(p.relative_to(root/'work/isolated-memory-control')):sha(p) for p in (root/'work/isolated-memory-control').rglob('*.swift') if '.build' not in p.parts},'commands':[]}
refs=[json.loads(s) for s in (root/'work/evidence/isolated-memory-direct/measurements.jsonl').read_text().splitlines()]
for size in [512,2048]:
 for profile in ['lossless16','dct12','xyb8']:
  jpeg=root/f'work/evidence/isolated-memory-direct/{profile}-{size}.jpg'
  for operation in ['encode','decode']:
   for repetition in range(3):
    for impl in ['predecessorAsync','predecessorAsyncCopy'] if operation=='decode' else ['predecessorAsync']:
     cmd=[str(binary),impl,operation,str(size),profile,str(jpeg)];r=subprocess.run(cmd,capture_output=True,text=True,check=True);x=json.loads(r.stdout);x['repetition']=repetition
     ref=next(v for v in refs if (v['size'],v['profile'],v['operation'])==(size,profile,operation));assert ref['outputSHA256']==x['outputSHA256'] and ref['outputBytes']==x['outputBytes']
     rows.append(x);meta['commands'].append(cmd)
     with (out/'measurements.jsonl').open('a') as f:f.write(json.dumps(x,sort_keys=True)+'\n')
  print('Control completed',size,profile,flush=True)
meta['status']='passed';meta['measurements']=len(rows);meta['allOutputHashesMatch']=True;meta['fileHashes']={p.name:sha(p) for p in out.iterdir() if p.is_file()};(out/'results.json').write_text(json.dumps(meta,indent=2)+'\n')
