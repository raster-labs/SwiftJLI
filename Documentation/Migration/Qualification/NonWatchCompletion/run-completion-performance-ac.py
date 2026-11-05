# SPDX-License-Identifier: Apache-2.0
"""Run fixed-reference public comparisons only after the full fuzz campaign stops."""
from pathlib import Path
import subprocess,time,json,hashlib,datetime,re
root=Path.cwd();evidence=root/'work/completion-evidence';fuzz=evidence/'fuzz/campaign.json'
while True:
 state=json.loads(fuzz.read_text()).get('status')
 if state=='failed':raise SystemExit('Fuzz failed; performance not started')
 if state=='passed':break
 time.sleep(10)
# Allow the CPU workload and scheduler to settle after the four fuzz processes.
time.sleep(60)
out=evidence/'performance-ac';out.mkdir(exist_ok=False)
binary=root/'work/completion-benchmark-build/out/Products/Release/Benchmark';repo=root/'work/SwiftJLI'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def power():
 text=subprocess.check_output(['pmset','-g','batt'],text=True)
 settings=subprocess.check_output(['pmset','-g','custom'],text=True)
 return {'battery':re.sub(r'\(id=\d+\)','(id=redacted)',text),'settings':settings,
         'thermal':subprocess.check_output(['pmset','-g','therm'],text=True)}
def mode(snapshot):return snapshot['battery'].splitlines()[0],snapshot['settings']
prior=json.loads((evidence/'performance/results.json').read_text())
assert sha(binary)==prior['binarySHA256'], 'Benchmark binary changed'
assert all(sha(repo/path)==digest for path,digest in prior['sourceHashes'].items()), 'Shipping input changed'
assert all(sha(root/'work/completion-benchmark'/path)==digest for path,digest in prior['harnessHashes'].items()), 'Harness changed'
start=power()
assert "'AC Power'" in start['battery'].splitlines()[0], 'AC power required'
record={'status':'running','revision':subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),
 'predecessor':'981da4efb7d62e4370c5d6de706d56a729b9552e','predecessorReason':'Same corrected full-resolution chroma output; original migration pin remains unchanged.',
 'startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'initialPower':start,
 'sourceHashes':{str(p.relative_to(repo)):sha(p) for p in [repo/'Package.swift',*sorted((repo/'Sources').rglob('*.swift'))]},
 'harnessHashes':{str(p.relative_to(root/'work/completion-benchmark')):sha(p) for p in (root/'work/completion-benchmark').rglob('*.swift')},
 'binarySHA256':sha(binary),'commands':[],'powerChecks':[],
 'ownerEnvironmentConfirmation':'Power connected; heavy applications idle. AC detected by pmset before execution.',
 'method':'Native ARM64 release, no sanitizer/tracer, 5 warmups and 20 interleaved timed iterations per implementation per case. Two expanded and two ordinary runs; no overlapping local codec builds or fuzzing. Power/thermal continuity required.',
 'limits':'One developer host and one sustained power mode; not a cross-device or laboratory population study.'}
def save():(out/'results.json').write_text(json.dumps(record,indent=2)+'\n')
save()
try:
 for label,args in [('extended-1',['--extended']),('normal-1',[]),('extended-2',['--extended']),('normal-2',[])]:
  print('Starting',label,flush=True)
  command=[str(binary),*args]
  with (out/(label+'.jsonl')).open('w') as stdout,(out/(label+'.stderr')).open('w') as stderr:
   child=subprocess.Popen(command,stdout=stdout,stderr=stderr)
   while child.poll() is None:
    current=power();record['powerChecks'].append({'run':label,'timeUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),**current})
    if mode(current)!=mode(start):
     child.terminate();child.wait(timeout=30);raise RuntimeError('Power mode changed; this run is not accepted')
    time.sleep(10)
  rows=[json.loads(s) for s in (out/(label+'.jsonl')).read_text().splitlines()]
  cases=[r for r in rows if r.get('event')=='case']
  assert child.returncode==0 and rows[-1]['event']=='complete'
  assert len(cases)==(60 if args else 10)
  assert all(r['codestreamsEqual'] and r['samplesEqual'] for r in cases)
  assert all(r[phase]['thermalState']==0 for r in cases for phase in ['before','after']), 'Non-nominal thermal state'
  record['commands'].append({'label':label,'argv':command,'exitCode':child.returncode,'cases':len(cases),
                            'logSHA256':sha(out/(label+'.jsonl'))})
  save()
 assert mode(power())==mode(start), 'Power mode changed at completion'
 record['status']='passed_execution_identity_and_environment_checks'
 record['performanceAcceptance']='Requires per-case interpretation; execution success alone is not acceptance.'
except BaseException as error:record['status']='failed';record['error']=repr(error);raise
finally:
 record['finalPower']=power();record['completedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
print('All four performance comparisons finished',flush=True)
