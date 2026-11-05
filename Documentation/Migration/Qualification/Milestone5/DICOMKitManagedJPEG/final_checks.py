from pathlib import Path
import subprocess,json
root=Path('/Users/pushparaj/projects/SwiftJLI-dicomkit-managed');scratch=Path('/private/tmp/swiftjli-qualified-adapter-probe')
products='/private/tmp/swiftjli-qualified-heap-final-build/build/out/Products/Release'
commands=[
 ('asan-tests-final.log',['xcrun','swift','test','--jobs','2','--scratch-path','/private/tmp/swiftjli-qualified-asan','--sanitize','address','--filter','QualifiedJPEGTests']),
 ('tsan-tests-final.log',['xcrun','swift','test','--jobs','2','--scratch-path','/private/tmp/swiftjli-qualified-tsan','--sanitize','thread','--filter','QualifiedJPEGTests']),
 ('parity-compile-final.log',['xcrun','swiftc','-O','-swift-version','6','-I',products,str(scratch/'parity-candidate.swift'),products+'/SwiftJLI.o','-o',str(scratch/'parity-candidate')]),
 ('parity-final.log',['python3',str(scratch/'parity.py')])]
results=[]
for name,args in commands:
 with (scratch/name).open('w') as log:r=subprocess.run(args,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=300)
 results.append({'argv':args,'cwd':str(root),'exitCode':r.returncode,'log':name})
 (scratch/'final-checks-command-receipt.json').write_text(json.dumps(results,indent=2)+'\n')
 print(name,r.returncode,flush=True)
 if r.returncode:raise SystemExit(r.returncode)
