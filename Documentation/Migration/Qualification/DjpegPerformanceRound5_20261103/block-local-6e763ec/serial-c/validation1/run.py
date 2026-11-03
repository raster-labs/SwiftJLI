from pathlib import Path
import subprocess,hashlib,json,datetime,time,os,re,sys
out=Path(__file__).resolve().parent
work=Path('/private/tmp/swiftjli-round5-group4-fma-serial-c')
scratch=Path('/private/tmp/swiftjli-round5-group4-fma-serial-c-build1')
receipt=out/'receipt.json';rev='8ecfc067f91988c30862d147b66adb82d24658e3'
assert not receipt.exists() and not scratch.exists(), 'Refusing existing receipt or scratch'
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def shac(p):
 h=hashlib.sha256()
 with Path(p).open('rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()
def capture(cmd):return subprocess.check_output(cmd,cwd=work,text=True).strip()
assert capture(['git','rev-parse','HEAD'])==rev
assert capture(['git','status','--porcelain'])==''
paths=capture(['git','ls-tree','-r','--name-only','HEAD','--','Package.swift','Sources','Tests']).splitlines()
source={p:shac(work/p) for p in paths}
compilerpaths={name:capture(['xcrun','--find',name]) for name in ['swift','swiftc','clang']}
frontend=Path(compilerpaths['swift']).parent/'swift-frontend';compilerpaths['swift-frontend']=str(frontend)
compiler={k:{'path':p,'realPath':str(Path(p).resolve()),'sha256':shac(p)} for k,p in compilerpaths.items()}
filter='CSequentialGreyscaleTests|SequentialGreyscaleDecoderTests|StreamingCoefficientReuseTests|StreamingWorkspaceAdmissionTests|BoundedDCTWorkspaceTests|CDCTDecoderTests|CACDecoderTests|CACPublicPipelineTests|PipelinedGreyscaleTests|ParallelGreyscaleWindowTests|ScopedACDecoderTests|ACLookaheadTests|BlockLocalIDCTTests|TinyDCOutputTests|CLosslessRow|LosslessRestartTests|NativeExecutionTests|CancellationPublicationTests|ParserReservationTests|Float32DecodeTests|EncoderDecoderTests|ProgressiveTests'
command=['xcrun','swift','test','--build-system','swiftbuild','-c','release','--jobs','4','--scratch-path',str(scratch),'--filter',filter]
r={'status':'running','candidateRevision':rev,'parentRevision':capture(['git','rev-parse','HEAD^']),'contract':'0.10.0','worktree':str(work),'scratchPath':str(scratch),'command':command,'sourceSHA256':source,'compiler':compiler,'swiftVersion':capture(['xcrun','swift','--version']),'xcodeVersion':capture(['xcodebuild','-version']),'sdkPath':capture(['xcrun','--show-sdk-path']),'selectedEnvironment':{k:os.environ[k] for k in ['DEVELOPER_DIR','SDKROOT','TOOLCHAINS'] if k in os.environ},'runnerSHA256':shac(__file__),'startedUTC':now(),'scope':'Focused correctness only; no benchmark timing authorised or executed.'}
receipt.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'status':'started','command':command,'sources':len(source)}),flush=True)
t=time.monotonic()
with (out/'stdout.log').open('x') as so,(out/'stderr.log').open('x') as se:
 result=subprocess.run(command,cwd=work,stdout=so,stderr=se)
r.update(exitCode=result.returncode,elapsedSeconds=time.monotonic()-t,finishedUTC=now())
r['sourceUnchanged']={p:shac(work/p)==h for p,h in source.items()};r['compilerUnchanged']={k:shac(v['path'])==v['sha256'] for k,v in compiler.items()};r['gitRevisionUnchanged']=capture(['git','rev-parse','HEAD'])==rev;r['gitClean']=capture(['git','status','--porcelain'])==''
r['stdoutSHA256']=shac(out/'stdout.log');r['stderrSHA256']=shac(out/'stderr.log');r['runnerUnchanged']=shac(__file__)==r['runnerSHA256']
log=(out/'stdout.log').read_text()+(out/'stderr.log').read_text();matches=re.findall(r'Test run with (\d+) tests? in (\d+) suites? passed',log);r['testSummary']=[{'tests':int(a),'suites':int(b)} for a,b in matches]
r['status']='passed' if result.returncode==0 and matches and all(r['sourceUnchanged'].values()) and all(r['compilerUnchanged'].values()) and r['gitRevisionUnchanged'] and r['gitClean'] and r['runnerUnchanged'] else 'failed'
artifacts={str(p):shac(p) for p in scratch.glob('out/Products/Release/SwiftJLI.o')};r['releaseSwiftObjectSHA256']=artifacts
receipt.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:r[k] for k in ['status','exitCode','elapsedSeconds','testSummary','releaseSwiftObjectSHA256']}),flush=True)
print('\n'.join(log.splitlines()[-12:]),flush=True)
sys.exit(0 if r['status']=='passed' else 1)
