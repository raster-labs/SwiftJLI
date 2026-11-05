#!/usr/bin/env python3
"""Prepared group4/FMA/parser candidate qualification; all parent failures retained. Execute only with CPU grant."""
import argparse,datetime,hashlib,json,os,pathlib,re,subprocess,time,traceback
ROOT=pathlib.Path(__file__).resolve().parent
REPO=pathlib.Path('/private/tmp/swiftjli-round5-flat-small-recovery')
PIN='bbc9ebe1a1e6c5fbe3839c697e562980d2a4a737'
FILTER='CSequentialGreyscaleTests|SmallLeftLosslessTests|DCZeroPairTests|DCOnlyGreyscaleDecoderTests|ParserReservationTests|StreamingWorkspaceAdmissionTests|ValidatedEnvelopeTests|BlockLocalIDCTTests|TinyDCCentreTests|TinyDCOutputTests|CLosslessRowTests|CLosslessRowPublicTests|CACDecoderTests|CDCTDecoderTests|CACPublicPipelineTests|ACLookaheadTests|ScopedACDecoderTests|SequentialGreyscale|PipelinedGreyscale|ParallelSequential|NativeExecutionTests|JPEGDecodeParityTests|BoundedDCTWorkspaceTests|EntropyBoundaryTests|CompressedInputOwnershipTests|OwnershipTests|LosslessRestartTests'
sha=lambda p:hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--gate',choices=['release','asan','tsan'],required=True);p.add_argument('--execute',action='store_true');p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
scratch='/private/tmp/swiftjli-round5-flat-small-recovery-'+a.gate+'-build'
command=['/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift','test','-c','release','--jobs','4','--scratch-path',scratch]
if a.gate!='release':command += ['--sanitize','address' if a.gate=='asan' else 'thread','--filter',FILTER]
if not a.execute:
 print(json.dumps({'status':'NOT EXECUTED','sourceRevision':PIN,'gate':a.gate,'command':command},indent=2));raise SystemExit(0)
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()==PIN
assert not subprocess.check_output(['git','status','--porcelain'],cwd=REPO)
source=json.loads((ROOT/'source.json').read_text())
for f in source['files']:assert sha(REPO/f['path'])==f['sha256']
a.output.mkdir(parents=True,exist_ok=False)
env=os.environ.copy();env['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
r={'status':'running','sourceRevision':PIN,'gate':a.gate,'command':command,'cwd':str(REPO),'environmentOverrides':{'DEVELOPER_DIR':env['DEVELOPER_DIR']},'sourceReceiptSHA256':sha(ROOT/'source.json'),'runnerSHA256':sha(__file__),'compilerSHA256':sha(command[0]),'startedUTC':now()}
def save():(a.output/'command.json').write_text(json.dumps(r,indent=2)+'\n')
save();start=time.monotonic()
try:
 with (a.output/'tests.log').open('w') as stream:
  result=subprocess.run(command,cwd=REPO,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=900)
 r['exitCode']=result.returncode
 text=(a.output/'tests.log').read_text();m=re.search(r'Test run with (\d+) tests in (\d+) suites passed',text)
 r['summary']={'tests':int(m[1]),'suites':int(m[2])} if m else None
 r['status']='passed' if r['exitCode']==0 and m else 'failed'
except BaseException as e:
 r.update(status='failed',failure=repr(e),traceback=traceback.format_exc())
r['compilerUnchanged']=sha(command[0])==r['compilerSHA256']
r.update(elapsedSeconds=time.monotonic()-start,finishedUTC=now(),logSHA256=sha(a.output/'tests.log'))
r['sourceUnchanged']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()==PIN and not subprocess.check_output(['git','status','--porcelain'],cwd=REPO)
r['sourceHashesUnchanged']=all(sha(REPO/f['path'])==f['sha256'] for f in source['files'])
save();print(json.dumps(r,indent=2));raise SystemExit(0 if r['status']=='passed' and r['sourceUnchanged'] and r['sourceHashesUnchanged'] and r['compilerUnchanged'] else 1)
