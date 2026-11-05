"""Serial-helper delta only: retained a81 workload; all samples and failures kept."""
from pathlib import Path
import datetime,hashlib,json,os,re,subprocess,shutil,statistics,sys
root=Path(__file__).resolve().parent;out=root/'native-dct-workers-1'
assert not out.exists(), 'Refusing existing benchmark directory'
compiler=Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
sdk='/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def git(w,*args):return subprocess.check_output(['git','-C',str(w),*args],text=True).strip()
parents={'baseline':('db1f5c7a31df33a8c6cf2264ab8f894aae302052',Path('/private/tmp/swiftjli-round5-group4-fma-parser'),Path('/private/tmp/swiftjli-round5-group4-fma-parser-release-build/out/Products/Release')),'candidate':('8ecfc067f91988c30862d147b66adb82d24658e3',Path('/private/tmp/swiftjli-round5-group4-fma-serial-c'),Path('/private/tmp/swiftjli-round5-group4-fma-serial-c-build1/out/Products/Release'))}
priorPath=Path('/private/tmp/swiftjli-round5-evidence/group4-fma-parser/native-dct-1/receipt.json');prior=json.loads(priorPath.read_text());testPath=root/'validation1/receipt.json';test=json.loads(testPath.read_text())
assert prior['candidateRevision']==parents['baseline'][0] and prior['status']=='complete'
assert test['candidateRevision']==parents['candidate'][0] and test['status']=='passed' and test['exitCode']==0
bindingPath=root/'validation1/artifact-binding.json';binding=json.loads(bindingPath.read_text())
assert binding['validationReceiptSHA256']==sha(testPath) and binding['candidateRevision']==parents['candidate'][0]
assert all(sha(path)==meta['sha256'] for path,meta in binding['artifacts'].items())
assert binding['nonDebugSectionComparison']['__TEXT,__text']['equalBytes'] and binding['nonDebugSectionComparison']['__TEXT,__text']['equalRawRelocations']
assert sha(compiler)==prior['compilerSHA256']==test['compiler']['swiftc']['sha256']
oldHarness=Path('/private/tmp/swiftjli-round5-evidence/c-row-serial-isolated/dct-workers.swift');harness=root/'dct-workers.swift'
assert harness.read_bytes()==oldHarness.read_bytes() and sha(harness)=='4e9e87dc0d089e91ceb8d0c9262548cf61dcfec07077cdd5b8ab280b064f5171'
assert sha(parents['baseline'][2]/'SwiftJLI.o')==prior['objects']['candidate']['sha256']
assert sha(parents['baseline'][2]/'SwiftJLIEntropyC.o')==prior['auxiliaryObjects']['candidate']['sha256']
assert all(sha(p)==h for p,h in prior['importedArtifacts']['candidate'].items())
assert sha(parents['candidate'][2]/'SwiftJLI.o')==test['releaseSwiftObjectSHA256'][str(parents['candidate'][2]/'SwiftJLI.o')]
fixtures=Path('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory');coverage=Path('/private/tmp/swiftjli-round2-dct-coverage')
cases=[fixtures/f'{kind}-{size}.jpg' for kind in ['dct12','rgb8','progressiveRGB8','xyb8'] for size in [512,2048]]+[coverage/f'{kind}-{bits}-512.jpg' for kind in ['flat','noise'] for bits in [8,12]]
source={};origin={};frozen={};snapshotLinks=[]
for label,(revision,work,products) in parents.items():
 assert git(work,'rev-parse','HEAD')==revision and git(work,'status','--porcelain')==''
 paths=git(work,'ls-tree','-r','--name-only','HEAD','--','Package.swift','Sources','Tests').splitlines()
 for path in paths:source[str(work/path)]=sha(work/path)
 if label=='candidate':assert all(source[str(work/p)]==h for p,h in test['sourceSHA256'].items())
 # Pin the complete C object set against the prior product/source identity too.
 for path in [products/'SwiftJLI.o',products/'SwiftJLIEntropyC.o']:
  origin[str(path)]=sha(path)
 modulemap=products.parent.parent/'Intermediates.noindex/GeneratedModuleMaps/SwiftJLIEntropyC.modulemap'
 header=Path(re.search(r'umbrella header "([^"]+)"',modulemap.read_text()).group(1));origin[str(modulemap)]=sha(modulemap);origin[str(header)]=sha(header)
 for path in (products/'SwiftJLI.swiftmodule').rglob('*'):
  if path.is_file():origin[str(path)]=sha(path)
assert (parents['baseline'][1]/'Sources/SwiftJLIEntropyC/LosslessCodeZeroRow.c').read_bytes()==(parents['candidate'][1]/'Sources/SwiftJLIEntropyC/LosslessCodeZeroRow.c').read_bytes()
out.mkdir()
r={'status':'preparing','startedUTC':now(),'baselineRevision':parents['baseline'][0],'candidateRevision':parents['candidate'][0],'priorReceiptSHA256':sha(priorPath),'validationReceiptSHA256':sha(testPath),'artifactBindingSHA256':sha(bindingPath),'harnessSHA256':sha(harness),'runnerSHA256':sha(__file__),'compilerSHA256':sha(compiler),'compilerVersion':subprocess.check_output([str(compiler),'--version'],text=True,stderr=subprocess.STDOUT),'sdk':sdk,'sourceSHA256':source,'originSHA256':origin,'fixtureSHA256':{str(p):sha(p) for p in cases},'commands':[],'records':[],'processes':[],'method':'Unchanged a81 harness/full12workload; each worker1/8, two rounds; immediately paired revisions, worker and revision order reversed in round2. Five warmups/20individual samples, full-output SHA256 and byte count outside timing. Input and verification-output lifetime unchanged.','limitations':'Serial-helper delta only; neither db1 nor8ecfc0 selected. Diagnostic8GiB workspace/10GiB total limits; no CLI/RSS claim or historical gate waiver.'}
def save(): (out/'receipt.json').write_text(json.dumps(r,indent=2)+'\n')
save()
try:
 for label,(revision,work,products) in parents.items():
  dest=out/('inputs-'+label);dest.mkdir()
  for name in ['SwiftJLI.o','SwiftJLIEntropyC.o']:
   shutil.copyfile(products/name,dest/name);assert sha(products/name)==sha(dest/name);snapshotLinks.append({'origin':str(products/name),'snapshot':str(dest/name),'sha256':sha(dest/name)})
  shutil.copytree(products/'SwiftJLI.swiftmodule',dest/'SwiftJLI.swiftmodule')
  for path in (dest/'SwiftJLI.swiftmodule').rglob('*'):
   if path.is_file():
    src=products/path.relative_to(dest);assert sha(src)==sha(path);snapshotLinks.append({'origin':str(src),'snapshot':str(path),'sha256':sha(path)})
  origmap=products.parent.parent/'Intermediates.noindex/GeneratedModuleMaps/SwiftJLIEntropyC.modulemap';header=Path(re.search(r'umbrella header "([^"]+)"',origmap.read_text()).group(1))
  shutil.copyfile(header,dest/'SwiftJLIEntropyC.h');assert sha(header)==sha(dest/'SwiftJLIEntropyC.h')
  snapshotLinks.append({'origin':str(header),'snapshot':str(dest/'SwiftJLIEntropyC.h'),'sha256':sha(header)})
  modulemap=dest/'SwiftJLIEntropyC.modulemap';modulemap.write_text(origmap.read_text().replace(str(header),str(dest/'SwiftJLIEntropyC.h')))
  snapshotLinks.append({'origin':str(origmap),'snapshot':str(modulemap),'onlyAdaptation':'umbrella header path to byte-exact frozen header','originSHA256':sha(origmap),'snapshotSHA256':sha(modulemap)})
  for path in dest.rglob('*'):
   if path.is_file():frozen[str(path)]=sha(path)
  command=[str(compiler),'-O','-parse-as-library','-target','arm64-apple-macos26.0','-sdk',sdk,'-I',str(dest),str(dest/'SwiftJLI.o'),str(dest/'SwiftJLIEntropyC.o'),'-Xcc','-fmodule-map-file='+str(modulemap),'-framework','Accelerate',str(harness),'-o',str(out/('dct-'+label))]
  entry={'label':label,'command':command};r['commands'].append(entry);save()
  with (out/(label+'-compile.stdout')).open('x') as so,(out/(label+'-compile.stderr')).open('x') as se:proc=subprocess.run(command,stdout=so,stderr=se)
  entry['exitCode']=proc.returncode;save();assert proc.returncode==0,'Harness compile failure'
 r['frozenSHA256']=frozen;r['snapshotLinks']=snapshotLinks;r['binarySHA256']={label:sha(out/('dct-'+label)) for label in parents};r['status']='running';save()
 with (out/'host.jsonl').open('x') as host:
  for rnd in [1,2]:
   for fixture in cases:
    for workers in ([1,8] if rnd==1 else [8,1]):
     pair={}
     for label in (['baseline','candidate'] if rnd==1 else ['candidate','baseline']):
      command=[str(out/('dct-'+label)),str(fixture),str(workers)]
      stem=f'round{rnd}-{fixture.stem}-workers{workers}-{label}';so=out/(stem+'.stdout');se=out/(stem+'.stderr')
      host.write(json.dumps({'utc':now(),'round':rnd,'fixture':fixture.name,'maximumWorkers':workers,'label':label,'loadAverage':os.getloadavg(),'processes':subprocess.check_output(['ps','-axo','pid,pcpu,comm'],text=True)})+'\n');host.flush()
      entry={'round':rnd,'fixture':fixture.name,'maximumWorkers':workers,'label':label,'command':command,'startedUTC':now(),'stdout':str(so),'stderr':str(se)};r['processes'].append(entry);save()
      with so.open('x') as stdout,se.open('x') as stderr:proc=subprocess.run(command,stdout=stdout,stderr=stderr)
      entry.update(exitCode=proc.returncode,finishedUTC=now(),stdoutSHA256=sha(so),stderrSHA256=sha(se));save();assert proc.returncode==0,'Decode failed; raw output retained'
      row=json.loads(so.read_text());r['records'].append({'round':rnd,'label':label,**row});save()
      assert row['fixture']==fixture.name and row['maximumWorkers']==workers and len(row['samplesSeconds'])==20
      assert statistics.median(row['samplesSeconds'])==row['medianSeconds'] and sorted(row['samplesSeconds'])[18]==row['p95Seconds']
      pair[label]=row
     assert (pair['baseline']['outputSHA256'],pair['baseline']['outputBytes'])==(pair['candidate']['outputSHA256'],pair['candidate']['outputBytes'])
     print(rnd,fixture.name,'workers',workers,round((pair['candidate']['medianSeconds']/pair['baseline']['medianSeconds']-1)*100,3),flush=True)
 assert len(r['records'])==96
 r['outputInvariantAcrossWorkersAndRounds']=all(len({(x['outputSHA256'],x['outputBytes']) for x in r['records'] if x['fixture']==f.name})==1 for f in cases)
 assert r['outputInvariantAcrossWorkersAndRounds']
 r['status']='complete'
except BaseException as error:
 r['status']='failed';r['error']=repr(error);raise
finally:
 checks={p:Path(p).is_file() and sha(p)==h for p,h in {**source,**origin,**frozen,**r['fixtureSHA256'],str(compiler):r['compilerSHA256'],str(harness):r['harnessSHA256'],str(Path(__file__)):r['runnerSHA256'],str(priorPath):r['priorReceiptSHA256'],str(testPath):r['validationReceiptSHA256'],str(bindingPath):r['artifactBindingSHA256']}.items()}
 checks.update({str(out/('dct-'+label)):sha(out/('dct-'+label))==h for label,h in r.get('binarySHA256',{}).items()})
 r['identityChecks']=checks;r['finishedUTC']=now()
 if not all(checks.values()):r['status']='failed-artifact-verification'
 save()
if r['status']!='complete':sys.exit(1)
print('All96 records retained; all12 outputs identical across workers/rounds/revisions.',flush=True)
