import datetime, hashlib, json, subprocess
from pathlib import Path
out=Path(__file__).parent
compiler=Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
sdk=Path('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk')
products={'round4':Path('/private/tmp/swiftjli-round4-build/out/Products/Release'),'round5_0d56':Path('/private/tmp/swiftjli-round5-combined-products'),'specialised':Path('/private/tmp/swiftjli-round5-lossless-build/out/Products/Release')}
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
prior=json.loads((out/'native.json').read_text())
r={'startedUTC':now(),'status':'compiling','revisions':prior['revisions'],'timingStatus':prior['timingStatus'],'compilerSHA256':sha(compiler),'runnerSHA256':sha(__file__),'harnessSHA256':{k:sha(out/f'{k}-matrix.swift') for k in ['flat','tiny']},'objects':{},'compileCommands':{},'binarySHA256':{},'runs':[]}
for label,p in products.items():
 assert sha(p/'SwiftJLI.o')==prior['linkedObjects'][label]['sha256']
 r['objects'][label]={'path':str(p/'SwiftJLI.o'),'sha256':sha(p/'SwiftJLI.o')}
 for kind in ['flat','tiny']:
  name=f'{kind}-{label}'
  command=[str(compiler),'-O','-parse-as-library','-swift-version','6','-strict-concurrency=complete','-target','arm64-apple-macos26.0','-sdk',str(sdk),'-I',str(p),str(p/'SwiftJLI.o'),'-framework','Accelerate',str(out/f'{kind}-matrix.swift'),'-o',str(out/name)]
  r['compileCommands'][name]=command
  with (out/f'{name}-compile.log').open('w') as log: subprocess.run(command,check=True,stdout=log,stderr=subprocess.STDOUT)
  r['binarySHA256'][name]=sha(out/name)
path=out/'focused.json'
def save(): path.write_text(json.dumps(r,indent=2)+'\n')
r['status']='running';save()
for n,order in enumerate([list(products),list(reversed(products))],1):
 for label in order:
  for kind in ['flat','tiny']:
   name=f'{kind}-{label}'
   (out/f'focused-processes-{name}-round{n}.txt').write_text(subprocess.check_output(['ps','-axo','pid,pcpu,comm'],text=True))
   command=[str(out/name)]+(['benchmark'] if kind=='flat' else [])+['/private/tmp/swiftjli-native-matrix-fixtures']
   run=subprocess.run(command,capture_output=True,text=True,check=True)
   (out/f'{name}-round{n}.jsonl').write_text(run.stdout)
   records=[json.loads(x) for x in run.stdout.splitlines()]
   assert len(records)==(3 if kind=='flat' else 4) and all(x['pixelExact'] for x in records)
   r['runs'].append({'round':n,'label':label,'kind':kind,'command':command,'exitCode':run.returncode,'records':records});save()
   print('Completed',name,'round',n,flush=True)
for name,digest in r['binarySHA256'].items(): assert sha(out/name)==digest
r['status']='complete';r['finishedUTC']=now();save()
for kind in ['flat','tiny']:
 cases=[x['case'] for x in next(run for run in r['runs'] if run['kind']==kind)['records']]
 for c in cases:
  v={label:[next(x['medianSeconds'] for x in run['records'] if x['case']==c) for run in r['runs'] if run['kind']==kind and run['label']==label] for label in products}
  print(kind,c,'medians_us',{k:[round(x*1e6,3) for x in xs] for k,xs in v.items()},'versusround4_pct',[100*(a/b-1) for a,b in zip(v['specialised'],v['round4'])],'versus0d56_pct',[100*(a/b-1) for a,b in zip(v['specialised'],v['round5_0d56'])],flush=True)
