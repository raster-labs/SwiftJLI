#!/usr/bin/env python3
"""Paired public-API native DCT benchmark, using two independently built modules."""
import argparse, hashlib, json, pathlib, subprocess, datetime, os
from provenance import import_snapshot, unchanged
p=argparse.ArgumentParser()
p.add_argument('--baseline-products',type=pathlib.Path,required=True)
p.add_argument('--candidate-products',type=pathlib.Path,required=True)
p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--rounds',type=int,default=2)
p.add_argument('--baseline-revision',default='ca0c1e874177f429ed199f3ed8ef6ac1315ee66a')
p.add_argument('--fixture-root',type=pathlib.Path,default=pathlib.Path('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory'))
p.add_argument('--coverage-root',type=pathlib.Path,default=pathlib.Path('/private/tmp/swiftjli-round2-dct-coverage'))
a=p.parse_args()
if a.output.parent.exists():raise SystemExit('Use a new result directory; refusing to overwrite retained artifacts')
compiler='/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
sdk='/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
harness=pathlib.Path('/private/tmp/swiftjli-round2-dct-benchmark.swift')
a.output.parent.mkdir(parents=True,exist_ok=True)
commands={};binaries={};objects={};auxiliaryObjects={};imports={}
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
for label,products in [('baseline',a.baseline_products),('candidate',a.candidate_products)]:
 binary=a.output.with_name(a.output.stem+'-'+label)
 obj=products/'SwiftJLI.o'
 objectHash=sha(obj)
 imports[label]=import_snapshot(products)
 cmd=[compiler,'-O','-parse-as-library','-target','arm64-apple-macos26.0','-sdk',sdk,'-I',str(products),str(obj),'-framework','Accelerate',str(harness),'-o',str(binary)]
 extra=products/'SwiftJLIEntropyC.o'
 if extra.is_file():
  modulemap=products.parent.parent/'Intermediates.noindex/GeneratedModuleMaps/SwiftJLIEntropyC.modulemap'
  cmd += [str(extra),'-Xcc','-fmodule-map-file='+str(modulemap)]
  auxiliaryObjects[label]={'path':str(extra),'sha256':sha(extra),'modulemap':str(modulemap),'modulemapSHA256':sha(modulemap)}
 with a.output.with_name(a.output.stem+'-'+label+'-compile.stdout').open('w') as outlog, a.output.with_name(a.output.stem+'-'+label+'-compile.stderr').open('w') as errlog:
  subprocess.run(cmd,check=True,stdout=outlog,stderr=errlog)
 assert sha(obj)==objectHash, 'Object changed during link'
 commands[label]=cmd;binaries[label]=binary;objects[label]={'path':str(obj),'sha256':objectHash}
fixtures=[a.fixture_root/f'{kind}-{size}.jpg' for kind in ['dct12','rgb8','progressiveRGB8','xyb8'] for size in [512,2048]]
fixtures += [a.coverage_root/f'{kind}-{bits}-512.jpg' for kind in ['flat','noise'] for bits in [8,12]]
fixtures += [pathlib.Path('/private/tmp/swiftjli-round5-dct-fixtures') / name for name in ['flat-8-19.jpg','flat-12-19.jpg','noise-8-19.jpg','noise-12-19.jpg','late-ac-8-512.jpg','late-ac-12-512.jpg']]
for fixture in fixtures:
 if not fixture.is_file():raise SystemExit(f'Missing fixture: {fixture}')
result={'baselineRevision':a.baseline_revision,'candidateRevision':'bbc9ebe1a1e6c5fbe3839c697e562980d2a4a737','timingStatus':'Advisory on shared host; no concurrent agent builds/tests/profiles during timing window.','startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'compilerSHA256':sha(pathlib.Path(compiler)),'compiler':subprocess.check_output([compiler,'--version'],text=True),'commands':commands,'objects':objects,'auxiliaryObjects':auxiliaryObjects,'importedArtifacts':imports,'provenanceSHA256':sha(pathlib.Path(__file__).with_name('provenance.py')),'harnessSHA256':sha(harness),'runnerSHA256':sha(pathlib.Path(__file__)),'hostLoadBefore':os.getloadavg(),'binarySHA256':{k:sha(v) for k,v in binaries.items()},'fixtureSHA256':{str(v):sha(v) for v in fixtures},'warmupsPerRun':5,'measuredSamplesPerRun':20,'records':[]}
a.output.write_text(json.dumps(result,indent=2)+'\n')
for trial in range(a.rounds):
 for fixture in fixtures:
  pair={}
  for label in (['baseline','candidate'] if trial%2==0 else ['candidate','baseline']):
   log=a.output.with_name(a.output.stem+'-'+str(trial+1)+'-'+fixture.stem+'-'+label)
   with log.with_suffix('.stdout.json').open('w') as stdout, log.with_suffix('.stderr.log').open('w') as stderr:
    subprocess.run([str(binaries[label]),str(fixture)],check=True,stdout=stdout,stderr=stderr)
   r=json.loads(log.with_suffix('.stdout.json').read_text())
   result['records'].append(dict(round=trial+1,label=label,**r));pair[label]=r
  a.output.write_text(json.dumps(result,indent=2)+'\n')
  assert pair['baseline']['outputSHA256']==pair['candidate']['outputSHA256'],str(fixture)
  assert pair['baseline']['outputBytes']==pair['candidate']['outputBytes'],str(fixture)
  print(fixture.name,trial+1,{k:round(v['medianSeconds']*1000,3) for k,v in pair.items()},flush=True)
  a.output.write_text(json.dumps(result,indent=2)+'\n')
result['hostLoadAfter']=os.getloadavg()
result['finishedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat()
result['status']='complete'
result['objectsUnchanged']=all(sha(pathlib.Path(v['path']))==v['sha256'] for v in objects.values())
result['auxiliaryObjectsUnchanged']=all(sha(pathlib.Path(v['path']))==v['sha256'] for v in auxiliaryObjects.values())
result['compilerUnchanged']=sha(pathlib.Path(compiler))==result['compilerSHA256']
result['binariesUnchanged']=all(sha(v)==result['binarySHA256'][k] for k,v in binaries.items())
result['harnessUnchanged']=sha(harness)==result['harnessSHA256']
result['runnerUnchanged']=sha(pathlib.Path(__file__))==result['runnerSHA256']
result['provenanceUnchanged']=sha(pathlib.Path(__file__).with_name('provenance.py'))==result['provenanceSHA256']
result['importsUnchanged']=all(unchanged(v) for v in imports.values())
result['fixturesUnchanged']=all(sha(pathlib.Path(p))==v for p,v in result['fixtureSHA256'].items())
result['status']='complete' if all(result[k] for k in ['objectsUnchanged','auxiliaryObjectsUnchanged','compilerUnchanged','importsUnchanged','fixturesUnchanged','binariesUnchanged','harnessUnchanged','runnerUnchanged','provenanceUnchanged']) else 'failed-artifact-verification'
a.output.write_text(json.dumps(result,indent=2)+'\n')
assert result['status']=='complete', 'Artifact verification failed'
print('All output SHA256 values and byte counts match.',flush=True)
