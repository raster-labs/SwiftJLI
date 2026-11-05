#!/usr/bin/env python3
"""Explicitly separate timing of newly admitted cases, without a prior Swift speedup claim."""
import argparse,array,datetime,hashlib,importlib.util,json,pathlib,re,statistics,subprocess,sys,time
p=argparse.ArgumentParser();p.add_argument('--candidate',type=pathlib.Path,required=True);p.add_argument('--baseline',type=pathlib.Path,required=True);p.add_argument('--source-revision',required=True);p.add_argument('--djpeg',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
repo=pathlib.Path('/private/tmp/swiftjli-djpeg-round5');helper=repo/'Scripts/benchmark-djpeg.py';spec=importlib.util.spec_from_file_location('benchmark_helpers',helper);h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
a.output.mkdir(parents=True,exist_ok=False);root=a.output;fixtures=pathlib.Path('/private/tmp/swiftjli-native-matrix-fixtures');cases=[('noise',2048),('noise',3072),('mixed',3072)]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
files=[a.candidate,a.baseline,a.djpeg,helper,pathlib.Path(__file__).resolve()]+[fixtures/f'{profile}-{size}.{ext}' for profile,size in cases for ext in ['jpg','raw']]
r={'status':'running','sourceRevision':a.source_revision,'baselineRevision':'5f9e1cf50db4eee4d5439f80602f3dfe9f24b0cd','startedUTC':now(),'method':'Newly admitted default-CLI cases only. Prior Swift must reject with resource exit5; no prior Swift timing or speedup is reported. Candidate and djpeg must both equal every original16-bit source sample. Five warmups,20 measured process launches per engine,2 rounds, rotated order per sample. PNM to/dev/null; time-l child peakRSS and full wrapper/launch elapsed wall time as existing CLI method. No resource override. Provisional shared-host timing; no concurrent local builds/tests/profiling.','inputSHA256':{str(f):sha(f) for f in files},'records':[],'commands':[],'hostLoadBefore':subprocess.check_output(['ps','-axo','pid,pcpu,comm'],text=True)}
def save():(root/'receipt.json').write_text(json.dumps(r,indent=2)+'\n')
def run(cmd,expected=0,stdout=subprocess.PIPE):
 row={'command':list(map(str,cmd)),'expectedExitCode':expected,'startedUTC':now()};r['commands'].append(row);save()
 try:q=subprocess.run(cmd,stdout=stdout,stderr=subprocess.PIPE,timeout=90)
 except BaseException as error:row.update(error=repr(error),finishedUTC=now());save();raise
 row.update(exitCode=q.returncode,finishedUTC=now());save()
 if q.returncode!=expected:row.update(stderr=q.stderr.decode(errors='replace')[-8192:]);save();raise RuntimeError(row)
 return q
def output_samples(data):
 descriptor,samples=h.parse_pnm(data);return descriptor,array.array('H',samples)
try:
 q=run([a.djpeg,'-version']);r['djpegVersion']=(q.stdout+q.stderr).decode();save()
 quality={}
 for profile,size in cases:
  fixture=fixtures/f'{profile}-{size}.jpg';commands={'candidate':[str(a.candidate),'decode','-i',str(fixture),'-o','-','--output-format','pnm'],'djpeg':[str(a.djpeg),str(fixture)]}
  old=run([str(a.baseline),'decode','-i',str(fixture),'-o','-','--output-format','pnm'],expected=5)
  assert b'resourceLimitExceeded' in old.stderr and old.stdout==b''
  source=array.array('H',(fixtures/f'{profile}-{size}.raw').read_bytes())
  if sys.byteorder!='little':source.byteswap()
  assert len(source)==size*size
  gate={'baselineExitCode':5,'baselineDiagnostic':old.stderr.decode(),'expectedSamples':len(source),'tolerance':0,'outputs':{}}
  for name,cmd in commands.items():
   q=run(cmd);assert not q.stderr
   descriptor,samples=output_samples(q.stdout);assert descriptor==('P5',size,size,65535) and samples==source
   gate['outputs'][name]={'sha256':hashlib.sha256(q.stdout).hexdigest(),'exactSourceSamples':True}
   del samples,q
  quality[(profile,size)]=(commands,gate);del source
 for round_number in [1,2]:
  for profile,size in cases:
   commands,gate=quality[(profile,size)];durations={name:[] for name in commands};rss={name:[] for name in commands}
   record={'profile':profile,'size':size,'round':round_number,'validation':gate,'commands':commands};r['partial']={'record':record,'elapsedSeconds':durations,'peakRSSBytes':rss};save()
   for iteration in range(-5,20):
    names=list(commands);shift=(iteration+round_number)%2;order=names[shift:]+names[:shift]
    if ((iteration+round_number)//2)%2:order.reverse()
    for name in order:
     cmd=commands[name]
     if iteration<0:
      q=run(cmd,stdout=subprocess.DEVNULL);assert not q.stderr;continue
     # Receipt writes are outside the measured subprocess interval, preserving
     # the earlier benchmark's wall-time boundary.
     entry={'command':['/usr/bin/time','-l',*cmd],'startedUTC':now()};r['commands'].append(entry);save()
     started=time.perf_counter_ns()
     q=h.run_bounded(entry['command'],90,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
     elapsed=(time.perf_counter_ns()-started)/1e9
     match=re.search(rb'\n\s*(\d+)\s+maximum resident set size',q.stderr);assert match
     entry.update(exitCode=q.returncode,finishedUTC=now());durations[name].append(elapsed);rss[name].append(int(match[1]));save()
   for name in commands:record[name]={'elapsedSeconds':h.stats(durations[name]),'peakRSSBytes':h.stats(rss[name])}
   r['records'].append(record);r.pop('partial',None);save();print(profile,size,round_number,{name:round(statistics.median(v)*1000,3) for name,v in durations.items()},flush=True)
 for f in files:assert sha(f)==r['inputSHA256'][str(f)]
 r.update(status='passed',finishedUTC=now(),hostLoadAfter=subprocess.check_output(['ps','-axo','pid,pcpu,comm'],text=True));save()
except BaseException as error:r.update(status='failed',failure=repr(error),finishedUTC=now());save();raise
