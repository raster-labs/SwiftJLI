import subprocess, json, hashlib, os, time
from pathlib import Path
out=Path('/private/tmp/swiftjli-round5-evidence/local-bounds')
compiler='/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
sdk='/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
products={'round3':Path('/private/tmp/swiftjli-round3-parser-build/out/Products/Release'),'round4':Path('/private/tmp/swiftjli-round4-build/out/Products/Release'),'candidate':Path('/private/tmp/swiftjli-round5-build/out/Products/Release')}
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
result={'candidate':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'baselineRound3':'8ae2762710d6279cd92222f5bb5ca95f042f694e','baselineRound4':'bbb0b1a9a602807643fc254fb4e0d54a162d5ae8','timingStatus':'provisional: external VM and cross-project workloads','compiler':{'path':compiler,'sha256':sha(compiler)},'harnessSHA256':sha(out/'tiny-matrix.swift'),'compileCommands':{},'objects':{},'binaries':{},'runs':[]}
for label,p in products.items():
 command=[compiler,'-O','-parse-as-library','-swift-version','6','-strict-concurrency=complete','-target','arm64-apple-macos26.0','-sdk',sdk,'-I',str(p),str(p/'SwiftJLI.o'),'-framework','Accelerate',str(out/'tiny-matrix.swift'),'-o',str(out/('tiny-'+label))]
 result['compileCommands'][label]=command;result['objects'][label]={'path':str(p/'SwiftJLI.o'),'sha256':sha(p/'SwiftJLI.o')}
 subprocess.run(command,check=True)
 result['binaries'][label]=sha(out/('tiny-'+label))
for n,order in enumerate([list(products),list(reversed(products))],1):
 for label in order:
  command=[str(out/('tiny-'+label)),'/private/tmp/swiftjli-native-matrix-fixtures']
  r=subprocess.run(command,capture_output=True,text=True,check=True)
  (out/f'tiny-{label}-round{n}.jsonl').write_text(r.stdout)
  result['runs'].append({'round':n,'label':label,'command':command,'exitCode':r.returncode,'records':[json.loads(x) for x in r.stdout.splitlines()]})
(out/'tiny-comparison.json').write_text(json.dumps(result,indent=2)+'\n')
for case in ['flat-19','ramp-19','noise-19','mixed-19']:
 v={k:sum(r['medianSeconds'] for run in result['runs'] if run['label']==k for r in run['records'] if r['case']==case)/2*1e6 for k in products}
 print(case,v, 'vsround4percent', (1-v['candidate']/v['round4'])*100)
