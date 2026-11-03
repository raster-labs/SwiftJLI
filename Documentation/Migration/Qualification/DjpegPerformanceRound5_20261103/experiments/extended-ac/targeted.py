import pathlib,subprocess,json,hashlib,datetime
p=pathlib.Path(__file__).parent
compiler='/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
sdk='/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
r={'reason':'Investigate repeated lossless flat/ramp outliers with immediate paired case ordering; retain original matrix unchanged.','timingStatus':'provisional','commands':[],'records':[]}
for name,products in [('baseline','/private/tmp/swiftjli-round5-704ddae-products'),('candidate','/private/tmp/swiftjli-round5-extended-build/out/Products/Release')]:
 cmd=[compiler,'-O','-parse-as-library','-target','arm64-apple-macos26.0','-sdk',sdk,'-I',products,products+'/SwiftJLI.o','-framework','Accelerate',str(p/'targeted.swift'),'-o',str(p/('targeted-'+name))]; q=subprocess.run(cmd,capture_output=True);r['commands'].append({'command':cmd,'exitCode':q.returncode});q.check_returncode()
for trial in range(4):
 for case in ['flat-512','flat-2048','flat-3072','ramp-2048','ramp-3072']:
  pair={}
  for name in (['baseline','candidate'] if trial%2==0 else ['candidate','baseline']):
   cmd=[str(p/('targeted-'+name)),'benchmark','/private/tmp/swiftjli-native-matrix-fixtures',case];q=subprocess.run(cmd,check=True,capture_output=True,text=True);v=json.loads(q.stdout);assert v['pixelExact'];r['records'].append({'round':trial+1,'label':name,**v});pair[name]=v
  print(trial+1,case,100*(pair['candidate']['medianSeconds']/pair['baseline']['medianSeconds']-1),flush=True)
  (p/'targeted-results.json').write_text(json.dumps(r,indent=2)+'\n')
r['status']='complete';r['hashes']={str(p/n):hashlib.sha256((p/n).read_bytes()).hexdigest() for n in ['targeted.swift','targeted-baseline','targeted-candidate']};(p/'targeted-results.json').write_text(json.dumps(r,indent=2)+'\n')
