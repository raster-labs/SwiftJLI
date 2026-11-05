#!/usr/bin/env python3
"""Default CLI admission and exact lossless samples; no timing or RSS claim."""
import argparse,datetime,hashlib,json,pathlib,subprocess,traceback
P=pathlib.Path;root=P(__file__).resolve().parent
ap=argparse.ArgumentParser();ap.add_argument('--output',type=P,required=True);a=ap.parse_args();a.output.mkdir(parents=True,exist_ok=False)
sha=lambda p:hashlib.sha256(P(p).read_bytes()).hexdigest()
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
fixtures=P('/private/tmp/swiftjli-native-matrix-fixtures')
binaries={'baseline':P('/private/tmp/swiftjli-round5-c-row-qualification-5f9e1cf-release-build/out/Products/Release/swiftjli-cli'),
'candidate':P('/private/tmp/swiftjli-round5-parser-reservation-release-build/out/Products/Release/swiftjli-cli'),
'djpeg':P('/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/djpeg')}
assert sha(binaries['baseline'])=='dfda666f9660b858743dc0008cc0c55217ff1426f3359cbca72e678c351fa5c8'
assert sha(binaries['candidate'])=='39a684f56965f0a6c86bd37c2189ae7376b915672973476780a17abf345a97eb'
wt=P('/private/tmp/swiftjli-round5-parser-reservation');pin='ca0c1e874177f429ed199f3ed8ef6ac1315ee66a'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=wt,text=True).strip()==pin
r={'status':'running','sourceRevision':pin,'baselineRevision':'5f9e1cf50db4eee4d5439f80602f3dfe9f24b0cd','startedUTC':now(),
'priorAttempt':'default-cli-admission-1 failed at baseline CLI argument validation because .pgm conflicted with --output-format pnm; no candidate decode ran. This version changes only output suffix to .pnm.',
'scope':'Newly admitted cases only, separate from unchanged-eligibility CLI timing. No timing or RSS claim. Full 16-bit sample equality to original source and djpeg3.2.1.',
'limits':'Unmodified default CLI limits: 512 MiB maximumWorkspaceBytes and 1 GiB maximumMemoryBytes, with existing CLI reservations deducted. No command passes a resource override.',
'pinnedInputs':{},'commands':[],'comparisons':[],'cases':[]}
def save():(a.output/'receipt.json').write_text(json.dumps(r,indent=2)+'\n')
def remember(p):r['pinnedInputs'][str(p)]=sha(p)
def command(cmd,label,expected):
 item={'label':label,'command':list(map(str,cmd)),'expectedExitCode':expected,'startedUTC':now()};r['commands'].append(item);save()
 try:p=subprocess.run(item['command'],capture_output=True,timeout=120);code=p.returncode;out=p.stdout;err=p.stderr
 except subprocess.TimeoutExpired as e:code=None;out=e.stdout or b'';err=e.stderr or b'';item['timeoutSeconds']=120
 (a.output/(label+'.stdout')).write_bytes(out);(a.output/(label+'.stderr')).write_bytes(err)
 item.update(exitCode=code,finishedUTC=now(),stdoutSHA256=sha(a.output/(label+'.stdout')),stderrSHA256=sha(a.output/(label+'.stderr')));save()
 assert code==expected,(label,code,err.decode(errors='replace'))
 return out,err

def pnm_payload(path,size):
 data=path.read_bytes();pos=0;tokens=[]
 for _ in range(4):
  while pos<len(data):
   if data[pos] in b' \t\r\n\v\f':pos+=1
   elif data[pos]==35:
    end=data.find(b'\n',pos);assert end>=0;pos=end+1
   else:break
  start=pos
  while pos<len(data) and data[pos] not in b' \t\r\n\v\f':pos+=1
  assert pos>start;tokens.append(data[start:pos])
 assert pos<len(data) and data[pos] in b' \t\r\n\v\f'
 pos+=2 if data[pos:pos+2]==b'\r\n' else 1
 assert tokens==[b'P5',str(size).encode(),str(size).encode(),b'65535'],tokens
 payload=data[pos:];assert len(payload)==size*size*2
 little=bytearray(len(payload));little[0::2]=payload[1::2];little[1::2]=payload[0::2]
 return little
try:
 remember(P(__file__));remember(root/'source.json');remember(wt/'Sources/SwiftJLI/Options.swift')
 for p in binaries.values():remember(p)
 command([binaries['djpeg'],'-version'],'djpeg-version',0)
 for stem in ['noise-2048','noise-3072','mixed-3072']:
  jpg=fixtures/(stem+'.jpg');raw=fixtures/(stem+'.raw');remember(jpg);remember(raw)
  size=int(stem.rsplit('-',1)[1]);case={'case':stem,'inputBytes':jpg.stat().st_size,'outputs':{}}
  r['cases'].append(case);save()
  for name in ['baseline','candidate','djpeg']:
   output=a.output/(stem+'-'+name+'.pnm')
   if name=='djpeg':cmd=[binaries[name],'-strict','-pnm','-outfile',output,jpg]
   else:cmd=[binaries[name],'decode','-i',jpg,'-o',output,'--output-format','pnm']
   _,err=command(cmd,stem+'-'+name,5 if name=='baseline' else 0)
   if name=='baseline':
    assert b'resourceLimitExceeded' in err
    case['baselineAdmission']='resourceLimitExceeded (exit5)'
    case['baselineOutputExists']=output.exists()
   else:
    expected=raw.read_bytes();actual=pnm_payload(output,size)
    row={'case':stem,'decoder':name,'allSamplesExact':actual==expected,'samplesCompared':size*size,
         'sourceSHA256':sha(raw),'actualLittleEndianSHA256':hashlib.sha256(actual).hexdigest(),
         'outputFile':str(output),'outputFileSHA256':sha(output),'outputBytes':output.stat().st_size,
         'descriptor':{'width':size,'height':size,'components':1,'maximumSample':65535}}
    r['comparisons'].append(row);case['outputs'][name]=row['outputFileSHA256'];save();assert row['allSamplesExact']
  case['candidateAdmission']='success (exit0) under unchanged defaults';save()
  print(stem,'baseline rejected; candidate and djpeg match every original16-bit sample',flush=True)
 r['identityChecks']={p:sha(p)==v for p,v in r['pinnedInputs'].items()};save();assert all(r['identityChecks'].values())
 assert not subprocess.check_output(['git','status','--porcelain'],cwd=wt,text=True).strip()
 assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=wt,text=True).strip()==pin
 r.update(status='passed',finishedUTC=now(),sourceUnchanged=True);save()
except BaseException as e:
 r.update(status='failed',failure=repr(e),traceback=traceback.format_exc(),finishedUTC=now());save();raise
