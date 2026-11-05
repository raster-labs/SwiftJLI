#!/usr/bin/env python3
import datetime,hashlib,json,os,subprocess,time
from pathlib import Path
root=Path(__file__).resolve().parents[2]
run=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
plan_path=root/'prepared.json'
assert sha(plan_path)=='881dadabc3900fe11aa0a7c04cf8079b4b98eab578a2d426289a02ae15efe4f5'
plan=json.loads(plan_path.read_text())
assert all(sha(p)==h for p,h in plan['inputs'].items())
built=json.loads((run/'build-helper.json').read_text())
helper=run/'swiftpm-testing-helper-x86_64'
assert built['exitCode']==0 and built['outputs'][str(helper)]==sha(helper)
architecture=subprocess.check_output(['/usr/bin/lipo','-archs',str(helper)],text=True).strip()
assert architecture=='x86_64'
command=[str(helper),'--test-bundle-path',plan['retainedBinary'],'--testing-library','swift-testing','--filter','CACPublicPipelineTests']
env=os.environ.copy();env['DYLD_FRAMEWORK_PATH']=plan['frameworkDirectory'];env['DEVELOPER_DIR']=plan['developerDirectory']
receipt={'sourceSHA256':sha(__file__),'parentCPUGrant':'Parent granted exclusive retained diagnostic plus focused Release after Int16 proof','preparedSHA256':sha(plan_path),'continuationOf':str(run/'retained.json'),'change':'Execute the same x86_64 helper directly, without the /usr/bin/arch launcher; architecture selects Rosetta. No binary or test change.','command':command,'cwd':str(run),'environmentOverrides':{k:env[k] for k in ['DYLD_FRAMEWORK_PATH','DEVELOPER_DIR']},'helperArchitecture':architecture,'helperSHA256':sha(helper),'retainedBinarySHA256':sha(plan['retainedBinary']),'startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exitCode':None,'qualificationLimits':plan['qualificationLimits']}
output=run/'retained-direct.json';log=run/'retained-direct.log'
assert not output.exists() and not log.exists()
output.write_text(json.dumps(receipt,indent=2)+'\n')
start=time.monotonic()
try:
 with log.open('wb') as f:receipt['exitCode']=subprocess.run(command,cwd=run,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=240).returncode
except subprocess.TimeoutExpired:receipt['failure']='Timed out; not passed'
receipt['elapsedSeconds']=time.monotonic()-start
receipt['logSHA256']=sha(log)
receipt['inputHashesUnchanged']=all(sha(p)==h for p,h in plan['inputs'].items())
receipt['helperUnchanged']=sha(helper)==receipt['helperSHA256']
receipt['finishedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat()
output.write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'receipt':str(output),'exitCode':receipt['exitCode'],'inputHashesUnchanged':receipt['inputHashesUnchanged']}),flush=True)
