#!/usr/bin/env python3
"""Frozen baseline/candidate public-API exactness and paired timing diagnostic."""
import argparse, datetime, hashlib, json, os, pathlib, re, subprocess, traceback
P = pathlib.Path
root = P(__file__).resolve().parent
ap=argparse.ArgumentParser(); ap.add_argument('--matrix', choices=['dct','lossless'], required=True); ap.add_argument('--output',type=P,required=True)
a=ap.parse_args(); a.output.mkdir(parents=True,exist_ok=False)
sha=lambda p:hashlib.sha256(P(p).read_bytes()).hexdigest()
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
compiler=P('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
sdk='/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
worktree=P('/private/tmp/swiftjli-round5-parser-reservation')
revision='ca0c1e874177f429ed199f3ed8ef6ac1315ee66a'
products={'baseline':P('/private/tmp/swiftjli-round5-c-row-qualification-5f9e1cf-release-build/out/Products/Release'),
'candidate':P('/private/tmp/swiftjli-round5-parser-reservation-release-build/out/Products/Release')}
assert sha(products['baseline']/'SwiftJLI.o')=='e2d04c7663b64c2a0d6d12efb527bb909a0aa6a8518e1be24102011eed6494f8'
assert sha(products['baseline']/'SwiftJLIEntropyC.o')=='af98e78a51b1ee9a0bb05e209d0081e1f5201f3c977e659d342717f2331f6a36'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=worktree,text=True).strip()==revision
assert not subprocess.check_output(['git','status','--porcelain'],cwd=worktree,text=True).strip()
assert not subprocess.check_output(['git','diff','5f9e1cf50db4eee4d5439f80602f3dfe9f24b0cd',revision,'--','Sources/SwiftJLIEntropyC','Package.swift'],cwd=worktree)
r={'status':'preparing','startedUTC':now(),'baselineRevision':'5f9e1cf50db4eee4d5439f80602f3dfe9f24b0cd','candidateRevision':revision,
'matrix':a.matrix,'method':'Paired each fixture; two rounds with reversed binary order; five warmup samples then twenty measured samples. Public allocated-output API. All input reads, output hashing and exactness checks outside timing. Individual decode timing excludes release; 19x19 lossless uses 500 decodes/sample and includes release.',
'limits':'Identical explicit 8 GiB workspace / 10 GiB total diagnostic budgets. Not default CLI admission or RSS evidence.',
'quality':'Lossless compared to entire retained source bytes; DCT compared to frozen baseline SHA/byte count; output identities asserted across both rounds.',
'hostCaveat':'Provisional shared-host timing; coordinated no local build/test/profiling overlap. Host snapshots retained; unrelated VM/process activity may affect samples.',
'cAndPackageSourceIdenticalToBaseline':True,'pinnedInputs':{},'commands':[],'records':[],'binaries':{}}
receipt=a.output/'receipt.json'
def save(): receipt.write_text(json.dumps(r,indent=2)+'\n')
def pin(p): r['pinnedInputs'][str(p)]=sha(p)
def command(cmd,name,timeout=600):
 item={'name':name,'command':list(map(str,cmd)),'startedUTC':now()};r['commands'].append(item);save()
 try:
  p=subprocess.run(item['command'],capture_output=True,timeout=timeout)
  item['exitCode']=p.returncode;stdout=p.stdout;stderr=p.stderr
 except subprocess.TimeoutExpired as e:
  item['exitCode']=None;item['timeoutSeconds']=timeout;stdout=e.stdout or b'';stderr=e.stderr or b''
 (a.output/(name+'.stdout')).write_bytes(stdout);(a.output/(name+'.stderr')).write_bytes(stderr)
 item.update(finishedUTC=now(),stdoutSHA256=sha(a.output/(name+'.stdout')),stderrSHA256=sha(a.output/(name+'.stderr')));save()
 if item['exitCode']!=0:raise RuntimeError('Command failed: '+name)
 return stdout.decode()
def snapshot(label):
 with (a.output/'host.jsonl').open('a') as f:f.write(json.dumps({'utc':now(),'label':label,'loadAverage':os.getloadavg(),'processes':subprocess.check_output(['ps','-axo','pid,pcpu,comm'],text=True)})+'\n')
def unchanged():
 checks={p:sha(p)==h for p,h in r['pinnedInputs'].items()};r['identityChecks']=checks;save();assert all(checks.values())
try:
 pin(compiler);pin(P(__file__));pin(root/'NativeMatrix.swift');pin(root/'source.json')
 r['compilerVersion']=command([compiler,'--version'],'compiler-version')
 r['xcodeVersion']=command(['xcodebuild','-version'],'xcode-version')
 if a.matrix=='dct':
  froot=P('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory');cover=P('/private/tmp/swiftjli-round2-dct-coverage')
  fixtures=[(froot/f'{k}-{s}.jpg',None) for k in ['dct12','rgb8','progressiveRGB8','xyb8'] for s in [512,2048]]
  fixtures += [(cover/f'{k}-{b}-512.jpg',None) for k in ['flat','noise'] for b in [8,12]]
 else:
  froot=P('/private/tmp/swiftjli-native-matrix-fixtures')
  fixtures=[(froot/f'{k}-{s}.jpg',froot/f'{k}-{s}.raw') for k in ['flat','ramp','noise','mixed'] for s in [19,512,2048,3072]]
 for jpg,raw in fixtures:
  pin(jpg)
  if raw:pin(raw)
 for name,folder in products.items():
  obj=folder/'SwiftJLI.o';extra=folder/'SwiftJLIEntropyC.o'
  modulemap=folder.parent.parent/'Intermediates.noindex/GeneratedModuleMaps/SwiftJLIEntropyC.modulemap'
  header=P(re.search(r'umbrella header "([^"]+)"',modulemap.read_text()).group(1))
  for p in [obj,extra,modulemap,header,*sorted((folder/'SwiftJLI.swiftmodule').glob('*'))]:pin(p)
  binary=a.output/('native-'+name)
  cmd=[compiler,'-O','-parse-as-library','-target','arm64-apple-macos26.0','-sdk',sdk,'-I',folder,obj,extra,'-Xcc','-fmodule-map-file='+str(modulemap),'-framework','Accelerate',root/'NativeMatrix.swift','-o',binary]
  command(cmd,'compile-'+name);pin(binary);r['binaries'][name]=str(binary)
 unchanged();r['status']='running';save()
 identities={}
 for round_no in [1,2]:
  for jpg,raw in fixtures:
   pair={}
   for name in (['baseline','candidate'] if round_no==1 else ['candidate','baseline']):
    label=f'round{round_no}-{jpg.stem}-{name}';snapshot(label)
    cmd=[r['binaries'][name],str(jpg)]+([str(raw)] if raw else [])
    row=json.loads(command(cmd,label));assert len(row['samplesSeconds'])==20
    if raw:assert row['sourceExact']
    ident=(row['outputSHA256'],row['outputBytes'],row['width'],row['height'])
    if str(jpg) in identities:assert identities[str(jpg)]==ident
    else:identities[str(jpg)]=ident
    r['records'].append(dict(round=round_no,label=name,**row));pair[name]=row;save()
   print(jpg.name,round_no,{k:round(v['medianSeconds']*1000,6) for k,v in pair.items()},flush=True)
 unchanged();snapshot('finished')
 assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=worktree,text=True).strip()==revision
 assert not subprocess.check_output(['git','status','--porcelain'],cwd=worktree,text=True).strip()
 r.update(status='complete',finishedUTC=now(),allOutputIdentitiesMatch=True,sourceUnchanged=True);save()
except BaseException as e:
 r.update(status='failed',failure=repr(e),traceback=traceback.format_exc(),finishedUTC=now());save();raise
