import json, pathlib, statistics, subprocess, time
root=pathlib.Path(__file__).parent
binary=root/'instrumented'/'swiftjli-cli'
fixtures=[pathlib.Path('/private/tmp/swiftjli-native-matrix-fixtures')/name for name in ['flat-19.jpg','flat-512.jpg','noise-512.jpg','flat-3072.jpg']]
fixtures.append(pathlib.Path('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory/dct12-512.jpg'))
result={'purpose':'Diagnostic attribution only; instrumented executable is never used for acceptance timing.','warmups':5,'samples':20,'records':[]}
for fixture in fixtures:
 cmd=[str(binary),'decode','-i',str(fixture),'-o','-','--output-format','pnm']
 rows=[]
 for iteration in range(25):
  start=time.perf_counter_ns()
  run=subprocess.run(cmd,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True,check=True)
  total=time.perf_counter_ns()-start
  phases={}
  for line in run.stderr.splitlines():
   prefix,name,value=line.split(); assert prefix=='PHASE'
   phases[name]=float(value)
  if iteration>=5:rows.append({'externalNanoseconds':total,'phasesNanoseconds':phases})
 summary={name:statistics.median([row['phasesNanoseconds'][name] for row in rows])/1e6 for name in rows[0]['phasesNanoseconds']}
 result['records'].append({'fixture':str(fixture),'command':cmd,'samples':rows,'medianCumulativeMilliseconds':summary,'medianExternalMilliseconds':statistics.median([r['externalNanoseconds'] for r in rows])/1e6})
 print(fixture.name,summary,flush=True)
(root/'phases.json').write_text(json.dumps(result,indent=2)+'\n')
