from pathlib import Path
import subprocess,json,hashlib
root=Path.cwd();out=root/'work/completion-evidence';repo=root/'work/SwiftJLI';image='swiftjli-completion-oracles:20261012-e7e54f7'
meta={'status':'running','commands':[], 'sourceSHA256':hashlib.sha256((repo/'Examples/SuitePairIntegration/Sources/SuitePairIntegration/main.swift').read_bytes()).hexdigest(), 'imageID':subprocess.check_output(['docker','image','inspect',image,'--format','{{.Id}}'],text=True).strip()}
def run(cmd,log):
 with (out/log).open('w') as f, (out/(log+'.stderr')).open('w') as err:r=subprocess.run(cmd,stdout=f,stderr=err,timeout=600)
 meta['commands'].append({'argv':cmd,'exitCode':r.returncode,'log':log})
 (out/'suite-linux-results.json').write_text(json.dumps(meta,indent=2)+'\n')
 if r.returncode:raise RuntimeError(log)
base=['docker','run','--rm','--network','none','-v',f'{root}/work/completion-suite-linux-build:/build:ro','-v',f'{out}:/evidence']
try:
 run(base+[image,'/build/release/SuitePairIntegration','/evidence/suite-linux-verified'], 'suite-linux.log')
 run(base+['-e','SWIFTJLI_COPY_CONTROL=1',image,'/build/release/SuitePairIntegration','/evidence/suite-linux-control-verified'], 'suite-linux-control.log')
 run(['python3',str(repo/'Scripts/verify-cross-codec-heap.py'),'--suite','--baseline',str(out/'suite-linux.log'),'--control',str(out/'suite-linux-control.log')], 'suite-linux-verification.log')
 run(base+[image,'strace','-f','-e','trace=open,openat,openat2,creat,memfd_create,execve,execveat','-o','/evidence/suite-file-access.log','/build/release/SuitePairIntegration','/evidence/suite-trace'], 'suite-trace.log')
 lines=(out/'suite-file-access.log').read_text().splitlines()
 writes=[line for line in lines if (any(call in line for call in ['open(', 'openat(', 'openat2(']) and ('O_WRONLY' in line or 'O_RDWR' in line)) or 'creat(' in line or 'memfd_create(' in line]
 execs=[line for line in lines if 'execve(' in line or 'execveat(' in line]
 assert len(writes)==72 and all('/evidence/suite-trace/' in line for line in writes), writes
 assert len(execs)==1 and '/build/release/SuitePairIntegration' in execs[0],execs
 meta.update(status='passed',finalCompressedWrites=len(writes),executedPrograms=len(execs))
except BaseException as error:meta.update(status='failed',error=repr(error));raise
finally:(out/'suite-linux-results.json').write_text(json.dumps(meta,indent=2)+'\n')
