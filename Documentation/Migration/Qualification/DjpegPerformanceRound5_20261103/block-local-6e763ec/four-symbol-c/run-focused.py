#!/usr/bin/env python3
import datetime,hashlib,json,os,subprocess,sys
from pathlib import Path
root=Path('/private/tmp/swiftjli-round5-code0-four-symbols')
evidence=Path(__file__).resolve().parent
out=evidence/'focused-release-1'
source=json.loads((evidence/'source.json').read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert not out.exists(), 'Refusing to overwrite a retained run'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()==source['sourceRevision']
assert not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()
assert all(sha(root/p)==h for p,h in source['sourceHashes'].items())
swift=Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift')
cmd=source['focusedReleaseCommand'];cmd[0]=str(swift)
out.mkdir()
env=os.environ.copy();env['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
receipt={'status':'running','sourceRevision':source['sourceRevision'],'baselineRevision':source['baselineRevision'],'command':cmd,'cwd':str(root),'sourceManifestSHA256':sha(evidence/'source.json'),'runnerSHA256':sha(__file__),'compilerSHA256':sha(swift),'startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'environmentOverrides':{'DEVELOPER_DIR':env['DEVELOPER_DIR']}}
(out/'command.json').write_text(json.dumps(receipt,indent=2)+'\n')
with (out/'tests.log').open('w') as log:
 result=subprocess.run(cmd,cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT)
receipt.update(exitCode=result.returncode,finishedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),logSHA256=sha(out/'tests.log'),compilerUnchanged=sha(swift)==receipt['compilerSHA256'],sourceUnchanged=all(sha(root/p)==h for p,h in source['sourceHashes'].items()),sourceStillClean=not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip())
receipt['status']='passed' if result.returncode==0 and receipt['compilerUnchanged'] and receipt['sourceUnchanged'] and receipt['sourceStillClean'] else 'failed'
(out/'command.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2));print('\n'.join((out/'tests.log').read_text().splitlines()[-12:]))
sys.exit(0 if receipt['status']=='passed' else 1)
