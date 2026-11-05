#!/usr/bin/env python3
"""Paired public-API native DCT benchmark, using two independently built modules."""
import argparse, hashlib, json, pathlib, subprocess, datetime
p=argparse.ArgumentParser()
p.add_argument('--baseline-products',type=pathlib.Path,required=True)
p.add_argument('--candidate-products',type=pathlib.Path,required=True)
p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--rounds',type=int,default=2)
p.add_argument('--fixture-root',type=pathlib.Path,default=pathlib.Path('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory'))
p.add_argument('--coverage-root',type=pathlib.Path,default=pathlib.Path('/private/tmp/swiftjli-round2-dct-coverage'))
a=p.parse_args()
compiler='/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
sdk='/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
harness=pathlib.Path('/private/tmp/swiftjli-round2-dct-benchmark.swift')
a.output.parent.mkdir(parents=True,exist_ok=True)
commands={};binaries={};objects={};auxiliaryObjects={}
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
for label,products in [('baseline',a.baseline_products),('candidate',a.candidate_products)]:
 binary=a.output.with_name(a.output.stem+'-'+label)
 obj=products/'SwiftJLI.o'
 cmd=[compiler,'-O','-parse-as-library','-target','arm64-apple-macos26.0','-sdk',sdk,'-I',str(products),str(obj),'-framework','Accelerate',str(harness),'-o',str(binary)]
 extra=products/'SwiftJLIEntropyC.o'
 if extra.is_file():
  modulemap=products.parent.parent/'Intermediates.noindex/GeneratedModuleMaps/SwiftJLIEntropyC.modulemap'
  cmd += [str(extra),'-Xcc','-fmodule-map-file='+str(modulemap)]
  auxiliaryObjects[label]={'path':str(extra),'sha256':sha(extra),'modulemap':str(modulemap),'modulemapSHA256':sha(modulemap)}
 subprocess.run(cmd,check=True)
 commands[label]=cmd;binaries[label]=binary;objects[label]={'path':str(obj),'sha256':sha(obj)}
fixtures=[a.fixture_root/f'{kind}-{size}.jpg' for kind in ['dct12','rgb8','progressiveRGB8','xyb8'] for size in [512,2048]]
fixtures += [a.coverage_root/f'{kind}-{bits}-512.jpg' for kind in ['flat','noise'] for bits in [8,12]]
for fixture in fixtures:
 if not fixture.is_file():raise SystemExit(f'Missing fixture: {fixture}')
result={'baselineRevision':'704ddae1bafea95d8a48c01ce35887c5b6413c0d','candidateRevision':'3a5ef320c04fff03561a69b705355c0e9da2fc31','timingStatus':'Advisory on shared host; no concurrent agent builds/tests/profiles during timing window.','startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'compilerSHA256':sha(pathlib.Path(compiler)),'compiler':subprocess.check_output([compiler,'--version'],text=True),'commands':commands,'objects':objects,'auxiliaryObjects':auxiliaryObjects,'harnessSHA256':sha(harness),'binarySHA256':{k:sha(v) for k,v in binaries.items()},'fixtureSHA256':{str(v):sha(v) for v in fixtures},'warmupsPerRun':5,'measuredSamplesPerRun':20,'records':[]}
for trial in range(a.rounds):
 for fixture in fixtures:
  pair={}
  for label in (['baseline','candidate'] if trial%2==0 else ['candidate','baseline']):
   r=json.loads(subprocess.check_output([str(binaries[label]),str(fixture)],text=True))
   result['records'].append(dict(round=trial+1,label=label,**r));pair[label]=r
  a.output.write_text(json.dumps(result,indent=2)+'\n')
  assert pair['baseline']['outputSHA256']==pair['candidate']['outputSHA256'],str(fixture)
  assert pair['baseline']['outputBytes']==pair['candidate']['outputBytes'],str(fixture)
  print(fixture.name,trial+1,{k:round(v['medianSeconds']*1000,3) for k,v in pair.items()},flush=True)
  a.output.write_text(json.dumps(result,indent=2)+'\n')
result['finishedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat()
result['status']='complete'
result['objectsUnchanged']=all(sha(pathlib.Path(v['path']))==v['sha256'] for v in objects.values())
result['auxiliaryObjectsUnchanged']=all(sha(pathlib.Path(v['path']))==v['sha256'] for v in auxiliaryObjects.values())
result['compilerUnchanged']=sha(pathlib.Path(compiler))==result['compilerSHA256']
a.output.write_text(json.dumps(result,indent=2)+'\n')
print('All output SHA256 values and byte counts match.',flush=True)
