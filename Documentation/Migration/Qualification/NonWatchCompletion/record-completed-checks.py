from pathlib import Path
import json,hashlib,subprocess,datetime
root=Path.cwd();repo=root/'work/SwiftJLI';e=root/'work/completion-evidence';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source={str(p.relative_to(repo)):sha(p) for p in [repo/'Package.swift',*sorted((repo/'Sources').rglob('*.swift'))]}
for name in source:
 data=subprocess.check_output(['git','-C',str(repo),'show','e7e54f7:'+name]);assert hashlib.sha256(data).hexdigest()==source[name]
for name,command,expected in [
 ('dct-interop',['python3','Scripts/verify-dct-interop.py','--output-dir','../completion-evidence/dct-interop','--scratch-path','../completion-oracle-build'],'48 DCT profiles passed both oracle directions; maximum sample difference 2'),
 ('lossless-interop',['python3','Scripts/verify-lossless-interop.py','--output-dir','../completion-evidence/lossless-interop','--scratch-path','../completion-oracle-build'],'210 verify cases passed')]:
 assert expected in (e/(name+'.log')).read_text()
 d={'status':'passed','recordedAfterExecutionUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command':command,'exitCode':0,'sourceRevision':'e7e54f756cccec07a66870ebefd68b5bbb5c79a6','sourceHashes':source,'result':expected,'logSHA256':sha(e/(name+'.log')),'fixtures':{p.name:sha(p)for p in sorted((e/name).iterdir())if p.is_file()},'tools':{n:subprocess.run([n,'-version'],capture_output=True,text=True).stderr.strip() for n in ['/opt/homebrew/bin/cjpeg','/opt/homebrew/bin/djpeg']}}
 (e/name/'qualification.json').write_text(json.dumps(d,indent=2)+'\n')
p=repo/'Examples/SuitePairIntegration';d={'status':'passed','sourceHashes':source,'harnessHashes':{str(f.relative_to(p)):sha(f)for f in p.rglob('*')if f.is_file()and f.suffix in ['.swift','.resolved','.cpp']},'nativeCases':72,'asanCases':72,'tsanCases':72,'commands':[]}
for label,cache,flags in [('pairs-final','completion-suite-build',[]),('asan','completion-suite-asan-build',['--sanitize','address']),('tsan','completion-suite-tsan-build',['--sanitize','thread'])]:
 log=e/('suite-'+label+'.log');assert sum(s.startswith('PASS ') for s in log.read_text().splitlines())==72
 d['commands'].append({'argv':['swift','run','--package-path','work/SwiftJLI/Examples/SuitePairIntegration','--scratch-path','work/'+cache,'-c','release',*flags,'SuitePairIntegration','work/completion-evidence/suite-'+label],'exitCode':0,'logSHA256':sha(log)})
(e/'suite-native-results.json').write_text(json.dumps(d,indent=2)+'\n')
print('Recorded source-bound oracle and suite results')
