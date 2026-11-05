import datetime,json,os,subprocess
from pathlib import Path
root=Path('/private/tmp/swiftjli-djpeg-round4');out=Path('/private/tmp/swiftjli-round4-evidence')
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
checks=[
 ('release-cli-final',['python3','Scripts/test-cli.py','--binary','/private/tmp/swiftjli-round4-build/out/Products/Release/swiftjli-cli','--output','/private/tmp/swiftjli-round4-final-cli']),
 ('asan-cli',['python3','Scripts/test-cli.py','--binary','/private/tmp/swiftjli-round4-asan/out/Products/Debug/swiftjli-cli','--output','/private/tmp/swiftjli-round4-asan-cli']),
 ('tsan-tests',['swift','test','--jobs','4','--scratch-path','/private/tmp/swiftjli-round4-tsan','--sanitize','thread','--filter','CompressedInputOwnershipTests|BoundedDCTWorkspaceTests|StreamingWorkspaceAdmissionTests|LosslessRestartTests|ZeroRunLosslessTests|SequentialGreyscaleDecoderTests|ValidatedEnvelopeTests|LosslessLookaheadTests|LosslessRowStorageTests|LosslessDifferenceTests|ScopedACDecoderTests|ACLookaheadTests|NativeExecutionTests|CLISynchronousExecutionTests|OwnershipTests|CancellationPublicationTests']),
 ('lossless-oracle',['python3','Scripts/verify-lossless-interop.py','--output-dir','/private/tmp/swiftjli-round4-lossless-oracle','--scratch-path','/private/tmp/swiftjli-round4-oracle-build','--cjpeg','/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/cjpeg','--djpeg','/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/djpeg']),
 ('dct-oracle',['python3','Scripts/verify-dct-interop.py','--output-dir','/private/tmp/swiftjli-round4-dct-oracle','--scratch-path','/private/tmp/swiftjli-round4-oracle-build','--cjpeg','/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/cjpeg','--djpeg','/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/djpeg']),
 ('contract-hashes',['shasum','-a','256','-c','COMMON_CONTRACT_SHA256.txt'])]
r={'sourceRevision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'startedUTC':now(),'environmentOverrides':{'DEVELOPER_DIR':env['DEVELOPER_DIR']},'checks':[]}
def save():(out/'validation.json').write_text(json.dumps(r,indent=2)+'\n')
for name,cmd in checks:
 print('Starting',name,flush=True)
 row={'name':name,'command':cmd,'cwd':str(root/'Documentation' if name=='contract-hashes' else root),'startedUTC':now(),'log':name+'.log'};r['checks'].append(row);save()
 with (out/row['log']).open('w') as log:p=subprocess.run(cmd,cwd=row['cwd'],env=env,stdout=log,stderr=subprocess.STDOUT)
 row.update(exitCode=p.returncode,finishedUTC=now());save()
 if p.returncode:raise SystemExit(p.returncode)
 print('Completed',name,flush=True)
r['finishedUTC']=now();save()
