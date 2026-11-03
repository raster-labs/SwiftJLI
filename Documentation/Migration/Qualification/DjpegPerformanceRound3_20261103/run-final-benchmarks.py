import datetime, hashlib, json, os, subprocess
from pathlib import Path
root=Path('/private/tmp/swiftjli-djpeg-round3')
out=Path('/private/tmp/swiftjli-round3-evidence/final')
prior=Path('/private/tmp/swiftjli-round2-final-build/out/Products/Release')
current=Path('/private/tmp/swiftjli-round3-parser-build/out/Products/Release')
compiler=Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
sha=lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
paths={'compiler':compiler,'baselineCLI':prior/'swiftjli-cli','candidateCLI':current/'swiftjli-cli','baselineLibrary':prior/'SwiftJLI.o','candidateLibrary':current/'SwiftJLI.o'}
for version in ['3.2.0','3.2.1']:paths['djpeg'+version]=Path('/opt/homebrew/Cellar/jpeg-turbo')/version/'bin/djpeg'
manifest={'baseline':'c7791d5635e46f3ef30f1dd1f14d7189e228a5c0','candidate':'5351088d3bb4630a32de6509e4d62210ad14aaa0','startedUTC':now(),'commands':[],'pins':{k:{'path':str(v),'sha256':sha(v)} for k,v in paths.items()},'powerBefore':subprocess.check_output(['pmset','-g','batt'],text=True)}
def save(): (out/'benchmark-commands.json').write_text(json.dumps(manifest,indent=2)+'\n')
save()
commands=[]
for version in ['3.2.1','3.2.0']:
 for matrix,fixtures in [('original','/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory'),('lossless-patterns','/private/tmp/swiftjli-native-matrix-fixtures')]:
  name='cli-'+matrix+'-'+version
  commands.append((name,['python3','Scripts/benchmark-djpeg.py','--baseline',str(paths['baselineCLI']),'--candidate',str(paths['candidateCLI']),'--djpeg',str(paths['djpeg'+version]),'--matrix',matrix,'--fixtures',fixtures,'--output',str(out/(name+'.json'))]))
commands.append(('native-lossless',['python3',str(out/'run-native-lossless.py'),'--candidate-products',str(current),'--output',str(out/'native-lossless.json')]))
commands.append(('native-dct',['python3','Documentation/Migration/Qualification/DjpegPerformanceRound2_20261102/swiftjli-round2-final-dct-benchmark.py','--baseline-products',str(prior),'--candidate-products',str(current),'--output',str(out/'native-dct.json')]))
for name,command in commands:
 print('Starting',name,flush=True)
 entry={'name':name,'command':command,'startedUTC':now(),'log':name+'.log'};manifest['commands'].append(entry);save()
 with (out/entry['log']).open('w') as log:r=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT)
 entry.update(exitCode=r.returncode,finishedUTC=now());save()
 if r.returncode: raise SystemExit(r.returncode)
 print('Completed',name,flush=True)
for k,v in paths.items():assert sha(v)==manifest['pins'][k]['sha256'],k+' changed'
manifest['powerAfter']=subprocess.check_output(['pmset','-g','batt'],text=True)
manifest['finishedUTC']=now();save()
