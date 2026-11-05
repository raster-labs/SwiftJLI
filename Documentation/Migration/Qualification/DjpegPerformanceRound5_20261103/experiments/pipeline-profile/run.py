#!/usr/bin/env python3
"""Compile a public-API profiler against an unchanged frozen object, then sample only its own processes."""
import argparse,hashlib,json,pathlib,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--build-only',action='store_true');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parent
products=pathlib.Path('/private/tmp/swiftjli-round5-704ddae-products')
compiler='/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
sdk='/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
source=root/'Profile.swift';binary=root/'profile-decode'
sha=lambda path:hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
cmd=[compiler,'-O','-g','-parse-as-library','-target','arm64-apple-macos26.0','-sdk',sdk,'-I',str(products),str(products/'SwiftJLI.o'),'-framework','Accelerate',str(source),'-o',str(binary)]
manifest={'note':'CPU sampling diagnosis only; no production edits or latency acceptance claims.',
 'productionSourceRevision':'14f35018d241666358480da2a8527d29ab047627',
 'frozenBuildRevision':'704ddae1bafea95d8a48c01ce35887c5b6413c0d',
 'compiler':subprocess.check_output([compiler,'--version'],text=True),'compilerSHA256':sha(compiler),
 'object':str(products/'SwiftJLI.o'),'objectSHA256':sha(products/'SwiftJLI.o'),
 'harnessSHA256':sha(source),'compileCommand':cmd,'runs':[]}
with (root/'compile.log').open('w') as out:
 result=subprocess.run(cmd,stdout=out,stderr=subprocess.STDOUT)
manifest['compileExitCode']=result.returncode
(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
result.check_returncode();manifest['binarySHA256']=sha(binary)
if not a.build_only:
 original=pathlib.Path('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory')
 coverage=pathlib.Path('/private/tmp/swiftjli-round2-dct-coverage')
 cases=[('dct12-512-w8',original/'dct12-512.jpg',8),('dct12-512-w1',original/'dct12-512.jpg',1),
        ('noise12-512-w8',coverage/'noise-12-512.jpg',8),('dct12-2048-w8',original/'dct12-2048.jpg',8)]
 for name,fixture,workers in cases:
  argv=[str(binary),str(fixture),str(workers),'6']
  with (root/(name+'.stderr')).open('w') as err:
   process=subprocess.Popen(argv,stdout=subprocess.PIPE,stderr=err,text=True)
   ready=process.stdout.readline().strip()
   if not ready.startswith('READY '):
    process.wait(timeout=10);raise RuntimeError((name,'profiler did not start',ready,process.returncode))
   sample=['/usr/bin/sample',str(process.pid),'4','1','-mayDie','-fullPaths','-file',str(root/(name+'.sample.txt'))]
   with (root/(name+'.sample-command.log')).open('w') as log:
    sampled=subprocess.run(sample,stdout=log,stderr=subprocess.STDOUT,timeout=10)
   stdout,_=process.communicate(timeout=10)
  (root/(name+'.stdout')).write_text(ready+'\n'+stdout)
  record={'case':name,'command':argv,'fixtureSHA256':sha(fixture),'sampleCommand':sample,
          'sampleExitCode':sampled.returncode,'processExitCode':process.returncode,
          'initialOutputSHA256':ready.split()[1]}
  if process.returncode==0:record['result']=json.loads(stdout)
  manifest['runs'].append(record)
  (root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
  print(name,'sample',sampled.returncode,'process',process.returncode,flush=True)
  if sampled.returncode or process.returncode:raise SystemExit('Profile failed; inspect logs')
manifest['objectUnchanged']=sha(products/'SwiftJLI.o')==manifest['objectSHA256']
(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
