#!/usr/bin/env python3
"""Parser-only sanitizer and CLI gates; requires --execute and assigned CPU slot."""
import argparse,datetime,hashlib,json,os,pathlib,re,subprocess,time,traceback
ROOT=pathlib.Path(__file__).resolve().parent
REPO=pathlib.Path('/private/tmp/swiftjli-round5-parser-reservation')
PIN='ca0c1e874177f429ed199f3ed8ef6ac1315ee66a'
FILTER='ParserReservationTests|ValidatedEnvelopeTests|StreamingWorkspaceAdmissionTests|CompressedInputOwnershipTests|OwnershipTests|NativeExecutionTests|JPEGDecodeParityTests|JPEGMigrationTests|LimitTests|MetadataTests|EntropyBoundaryTests|CLosslessRowPublicTests|CACPublicPipelineTests'
sha=lambda p:hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--gate',choices=['asan','tsan','cli'],required=True);p.add_argument('--execute',action='store_true');p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
source=json.loads((ROOT/'source.json').read_text())
if a.gate=='cli':
 binary=source['unchangedReleaseCLI']['path']
 command=['python3','Scripts/test-cli.py','--binary',binary,'--output',str(a.output.resolve()/'process-checks')]
else:
 command=['swift','test','-c','release','--jobs','4','--scratch-path','/private/tmp/swiftjli-round5-parser-reservation-'+a.gate+'-build','--sanitize','address' if a.gate=='asan' else 'thread','--filter',FILTER]
if not a.execute:
 print(json.dumps({'status':'NOT EXECUTED','sourceRevision':PIN,'gate':a.gate,'command':command},indent=2));raise SystemExit(0)
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()==PIN
assert not subprocess.check_output(['git','status','--porcelain'],cwd=REPO)
for f in source['files']:assert sha(REPO/f['path'])==f['sha256']
if a.gate=='cli':assert sha(binary)==source['unchangedReleaseCLI']['sha256']
a.output.mkdir(parents=True,exist_ok=False)
env=os.environ.copy();env['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
r={'status':'running','sourceRevision':PIN,'gate':a.gate,'command':command,'cwd':str(REPO),'environmentOverrides':{'DEVELOPER_DIR':env['DEVELOPER_DIR']},'sourceReceiptSHA256':sha(ROOT/'source.json'),'runnerSHA256':sha(__file__),'startedUTC':now()}
def save():(a.output/'command.json').write_text(json.dumps(r,indent=2)+'\n')
save();start=time.monotonic()
try:
 with (a.output/'output.log').open('w') as stream:
  result=subprocess.run(command,cwd=REPO,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=900)
 r['exitCode']=result.returncode
 if a.gate=='cli':
  report=json.loads((a.output/'process-checks/report.json').read_text())
  r['summary']={'checks':report.get('checks'),'status':report['status']}
  r['innerReportSHA256']=sha(a.output/'process-checks/report.json')
  r['binaryUnchanged']=sha(binary)==source['unchangedReleaseCLI']['sha256']
  r['status']='passed' if result.returncode==0 and report['status']=='passed' and report.get('checks')==252 and r['binaryUnchanged'] else 'failed'
 else:
  text=(a.output/'output.log').read_text();m=re.search(r'Test run with (\d+) tests in (\d+) suites passed',text)
  r['summary']={'tests':int(m[1]),'suites':int(m[2])} if m else None
  r['status']='passed' if r['exitCode']==0 and m else 'failed'
except BaseException as e:
 r.update(status='failed',failure=repr(e),traceback=traceback.format_exc())
r.update(elapsedSeconds=time.monotonic()-start,finishedUTC=now(),logSHA256=sha(a.output/'output.log'))
r['sourceUnchanged']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()==PIN and not subprocess.check_output(['git','status','--porcelain'],cwd=REPO)
r['sourceHashesUnchanged']=all(sha(REPO/f['path'])==f['sha256'] for f in source['files'])
save();print(json.dumps(r,indent=2));raise SystemExit(0 if r['status']=='passed' and r['sourceUnchanged'] and r['sourceHashesUnchanged'] else 1)
