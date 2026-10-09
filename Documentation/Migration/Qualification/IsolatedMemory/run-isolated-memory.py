import pathlib,subprocess,json,hashlib
root=pathlib.Path.cwd();out=root/'work/evidence/isolated-memory-direct';out.mkdir(exist_ok=False)
binary=root/'work/build-isolated-memory/arm64-apple-macosx/release/Memory';repo=root/'work/SwiftJLI';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
meta={'binarySHA256':sha(binary),'sourceHashes':{str(p.relative_to(repo)):sha(p) for p in [repo/'Package.swift',*sorted((repo/'Sources').rglob('*.swift'))]},'predecessor':'0a4ded0b0b2e8e38127f4f302b286e74ee352474','commands':[],'status':'running'}
rows=[]
try:
 for size in [512,2048]:
  for profile in ['lossless16','dct12','rgb8','progressiveRGB8','xyb8']:
   jpeg=out/f'{profile}-{size}.jpg';cmd=[str(binary),'predecessor','prepare',str(size),profile,str(jpeg)];subprocess.run(cmd,check=True);meta['commands'].append(cmd)
   for operation in ['encode','decode']:
    for repetition in range(3):
     pair=[]
     for impl in ['predecessor','successor'] if repetition%2==0 else ['successor','predecessor']:
      cmd=[str(binary),impl,operation,str(size),profile,str(jpeg)]
      r=subprocess.run(cmd,text=True,capture_output=True,check=True);x=json.loads(r.stdout);x['repetition']=repetition;rows.append(x);pair.append(x);meta['commands'].append(cmd)
      with (out/'measurements.jsonl').open('a') as f:f.write(json.dumps(x,sort_keys=True)+'\n')
     assert pair[0]['outputSHA256']==pair[1]['outputSHA256'] and pair[0]['outputBytes']==pair[1]['outputBytes']
   print('Completed',size,profile,flush=True)
 meta['status']='passed';meta['measurements']=len(rows);meta['allOutputHashesMatch']=True
except BaseException as e:meta['status']='failed';meta['error']=repr(e);raise
finally:
 meta['fileHashes']={p.name:sha(p) for p in out.iterdir() if p.is_file()};(out/'results.json').write_text(json.dumps(meta,indent=2)+'\n')
