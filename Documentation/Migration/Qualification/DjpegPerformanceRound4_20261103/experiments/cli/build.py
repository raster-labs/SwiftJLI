import json, pathlib, subprocess
root=pathlib.Path(__file__).parent
products=pathlib.Path('/private/tmp/swiftjli-round3-parser-build/out/Products/Release')
compiler='/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
sdk='/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
records=[]
for name in ['instrumented','baseline','candidate']:
 source = pathlib.Path('/private/tmp/swiftjli-round4-cli/Sources/SwiftJLICLI/main.swift') if name=='candidate' else root/name/'main.swift'
 cmd=[compiler,'-O','-whole-module-optimization','-swift-version','6','-strict-concurrency=complete','-module-name','SwiftJLICLI','-package-name','swiftjli_djpeg_round3','-target','arm64-apple-macos26.0','-sdk',sdk,'-I',str(products),str(products/'SwiftJLI.o'),'-framework','Accelerate',str(source),'-o',str(root/name/'swiftjli-cli')]
 with (root/f'build-{name}.log').open('w') as log: result=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
 records.append({'name':name,'command':cmd,'exitCode':result.returncode})
 (root/'build-commands.json').write_text(json.dumps(records,indent=2)+'\n')
 print(name,result.returncode,flush=True)
 result.check_returncode()
