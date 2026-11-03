from pathlib import Path
import datetime,json,subprocess,time
root=Path('/private/tmp/swiftjli-round5-c-row-composed')
p=Path(__file__).resolve().parent
pin='5f9e1cf50db4eee4d5439f80602f3dfe9f24b0cd'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()==pin
assert not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()
command=['xcrun','swift','test','--build-system','swiftbuild','-c','release','--jobs','4','--scratch-path','/private/tmp/swiftjli-round5-c-row-composed-build','--filter','CLosslessRow|LosslessLeftUInt16Tests|LosslessRowStorageTests|LosslessRestartTests|LosslessDifferenceTests|LosslessLookaheadTests|ZeroRunLosslessTests|CACDecoderTests|CDCTDecoderTests|CACPublicPipelineTests|NativeExecutionTests|CancellationPublication']
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
receipt={'source':pin,'command':command,'startedUTC':now()}
start=time.monotonic()
with (p/'tests.log').open('w') as log:
    run=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT)
receipt.update(exitCode=run.returncode,elapsedSeconds=time.monotonic()-start,finishedUTC=now())
(p/'tests.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2),flush=True)
print('\n'.join((p/'tests.log').read_text().splitlines()[-10:]),flush=True)
raise SystemExit(run.returncode)
