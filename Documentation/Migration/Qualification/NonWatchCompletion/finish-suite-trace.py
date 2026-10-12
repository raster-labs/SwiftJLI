from pathlib import Path
import subprocess,json,time
root=Path.cwd();e=root/'work/completion-evidence';a=e/'attribution/results.json'
while True:
 if a.exists():
  d=json.loads(a.read_text());s=d.get('status')
  if s=='failed':raise SystemExit('Attribution failed; resolve before final trace')
  if s=='passed_output_checks':break
 time.sleep(10)
cmd=['docker','run','--rm','--network','none','-v',f'{root}/work/completion-suite-linux-build:/build:ro','-v',f'{e}:/evidence','swiftjli-completion-oracles:20261012-e7e54f7','strace','-f','-e','trace=open,openat,openat2,creat,memfd_create,execve,execveat','-o','/evidence/suite-file-access-complete.log','/build/release/SuitePairIntegration','/evidence/suite-trace-complete']
with (e/'suite-trace-complete.log').open('w') as out,(e/'suite-trace-complete.stderr').open('w') as err:r=subprocess.run(cmd,stdout=out,stderr=err,timeout=120)
assert r.returncode==0
lines=(e/'suite-file-access-complete.log').read_text().splitlines()
writes=[l for l in lines if (any(c in l for c in ['open(', 'openat(', 'openat2(']) and ('O_WRONLY' in l or 'O_RDWR' in l)) or 'creat(' in l or 'memfd_create(' in l]
execs=[l for l in lines if 'execve(' in l or 'execveat(' in l]
assert len(writes)==72 and all('/evidence/suite-trace-complete/'in l for l in writes),writes
assert len(execs)==1 and '/build/release/SuitePairIntegration'in execs[0],execs
p=e/'suite-linux-results.json';d=json.loads(p.read_text());d['commands'].append({'argv':cmd,'exitCode':0,'log':'suite-file-access-complete.log'});d['completeFileAndProcessTrace']={'finalCompressedWrites':72,'executedPrograms':1,'syscalls':['open','openat','openat2','creat','memfd_create','execve','execveat']};p.write_text(json.dumps(d,indent=2)+'\n');print('Complete syscall trace passed')
