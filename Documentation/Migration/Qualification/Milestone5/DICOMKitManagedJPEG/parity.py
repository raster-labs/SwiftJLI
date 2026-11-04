from pathlib import Path
import re,base64,subprocess,hashlib,json
root=Path('/Users/pushparaj/projects/SwiftJLI-dicomkit-managed');scratch=Path('/private/tmp/swiftjli-qualified-adapter-probe');corpus=scratch/'parity-corpus';corpus.mkdir(exist_ok=True)
cases=[]
s=(root/'Tests/SwiftJLITests/ChromaReferenceFixtures.swift').read_text()
for name,width,height,jpeg in re.findall(r'Fixture\(name: "([^"]+)", width: (\d+), height: (\d+),\s+jpeg: "([^"]+)"',s):
 if name.startswith('baseline_'):
  p=corpus/(name+'.jpg');p.write_bytes(base64.b64decode(jpeg))
  for colour in ['auto','rgb','ycbcr']:cases.append((name,p,'rgb',colour))
s=(root/'Tests/SwiftJLITests/Native/LosslessRestartTests.swift').read_text()
for bits in [8,12]:
 text=s.split(f'static let cjpegRestart{bits}: [UInt8] = [',1)[1].split(']',1)[0]
 p=corpus/f'lossless{bits}.jpg';p.write_bytes(bytes(int(v,16) for v in re.findall(r'0x([0-9A-Fa-f]+)',text)))
 cases.append((f'lossless{bits}',p,'lossless','auto'))
results=[]
for name,jpeg,mode,colour in cases:
 rec={'name':name,'mode':mode,'colour':colour,'jpegSHA256':hashlib.sha256(jpeg.read_bytes()).hexdigest(),'commands':[]}
 output=[]
 for side in ['predecessor','candidate']:
  path=corpus/(name+'-'+colour+'-'+side+'.bin');args=[str(scratch/('parity-'+side)),str(jpeg),mode,colour,str(path)]
  r=subprocess.run(args,capture_output=True,timeout=30)
  rec['commands'].append({'argv':args,'exitCode':r.returncode,'stderr':r.stderr.decode(errors='replace')})
  if r.returncode:raise RuntimeError(rec)
  output.append(path.read_bytes())
 rec['exact']=output[0]==output[1];rec['bytes']=len(output[0]);rec['outputSHA256']=hashlib.sha256(output[0]).hexdigest()
 results.append(rec)
 if not rec['exact']:raise RuntimeError(rec)
receipt={'predecessorPin':'b6df774a3c3ecdf4b98971f31543fdd18074ace2','purpose':'exact caller-kernel pixel parity, not performance; predecessorDebug objects versus candidateRelease objects','cases':results,'allExact':all(x['exact'] for x in results)}
(scratch/'parity-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('exact cases',len(results))
