import datetime, hashlib, json, subprocess
from pathlib import Path
root=Path('/private/tmp/swiftjli-round3-zero-oracle');root.mkdir(exist_ok=True)
binary=Path('/private/tmp/swiftjli-round3-parser-build/out/Products/Release/swiftjli-cli')
cjpeg=Path('/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/cjpeg');djpeg=cjpeg.with_name('djpeg')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
result={'candidateRevision':'5351088d3bb4630a32de6509e4d62210ad14aaa0','startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'pins':{str(p):sha(p) for p in [binary,cjpeg,djpeg]},'cases':[]}
out=Path('/private/tmp/swiftjli-round3-evidence/zero-oracle.json')
for bits in [8,12,16]:
 for pattern in ['flat','plateau']:
  w,h=129,131;maximum=(1<<bits)-1
  samples=[maximum//2 if pattern=='flat' else ((x//31+y//17)*19)&maximum for y in range(h) for x in range(w)]
  raw=bytes(samples) if bits==8 else b''.join(v.to_bytes(2,'big') for v in samples)
  source=root/f'{bits}-{pattern}.pgm';source.write_bytes(f'P5\n{w} {h}\n{maximum}\n'.encode()+raw)
  for pt in [0,2]:
   for rows in [0,1,3]:
    jpeg=root/f'{bits}-{pattern}-pt{pt}-r{rows}.jpg'
    cmd=[str(cjpeg),'-precision',str(bits),'-lossless',f'1,{pt}','-optimize','-restart',str(rows),'-outfile',str(jpeg),str(source)]
    subprocess.run(cmd,check=True,capture_output=True)
    b=jpeg.read_bytes();p=2;eligible=False
    while p<len(b)-4:
     marker=b[p+1];n=int.from_bytes(b[p+2:p+4],'big');segment=b[p+4:p+2+n]
     if marker==196 and segment[0]==0:eligible=segment[1]==1 and segment[17]==0
     if marker==218:break
     p+=n+2
    assert eligible,'Oracle fixture does not exercise one-bit zero category'
    expected=[(v>>pt)<<pt for v in samples]
    expectedRaw=bytes(expected) if bits==8 else b''.join(v.to_bytes(2,'big') for v in expected)
    commands=[ [str(binary),'decode','-i',str(jpeg),'-o','-','--output-format','pnm'],[str(djpeg),'-strict','-pnm',str(jpeg)]]
    hashes=[]
    for command in commands:
     r=subprocess.run(command,check=True,capture_output=True);assert not r.stderr
     magic,geometry,maxval,pixels=r.stdout.split(b'\n',3)
     assert magic==b'P5' and geometry==f'{w} {h}'.encode() and int(maxval)==maximum
     assert pixels==expectedRaw
     hashes.append(hashlib.sha256(r.stdout).hexdigest())
    result['cases'].append({'bits':bits,'pattern':pattern,'pointTransform':pt,'restartRows':rows,'sourceSHA256':sha(source),'jpegSHA256':sha(jpeg),'oneBitZeroCategory':eligible,'commands':[cmd]+commands,'outputSHA256':hashes,'sampleExact':True})
    out.write_text(json.dumps(result,indent=2)+'\n')
result['finishedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat();result['status']='passed'
out.write_text(json.dumps(result,indent=2)+'\n')
print(len(result['cases']),'independent large zero-category fixtures passed both decoders with exact samples')
