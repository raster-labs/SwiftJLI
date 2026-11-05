import datetime,hashlib,json,pathlib,subprocess
root=pathlib.Path(__file__).parent
repo=pathlib.Path('/private/tmp/swiftjli-djpeg-round5')
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
def load():
 rows=[]
 for line in subprocess.check_output(['ps','-axo','pid,pcpu,comm'],text=True).splitlines()[1:]:
  x=line.split(None,2)
  if len(x)==3 and float(x[1])>=10:rows.append({'pid':int(x[0]),'cpuPercent':float(x[1]),'process':x[2]})
 return rows
r={'baseline':'bbb0b1a9a602807643fc254fb4e0d54a162d5ae8','candidate':'f4a05be9f3003a48adaa840abd48fcf6071f009d','timingStatus':'provisional under unrelated sharedhost activity; no localbuild/test/profiling overlaps','commands':[],'status':'running'}
for version in ['3.2.1','3.2.0']:
 for matrix in ['original','lossless-patterns']:
  name='cli-'+matrix+'-'+version
  fixtures='/private/tmp/swiftjli-native-matrix-fixtures' if matrix=='lossless-patterns' else '/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory'
  cmd=['python3','Scripts/benchmark-djpeg.py','--baseline','/private/tmp/swiftjli-round4-build/out/Products/Release/swiftjli-cli','--candidate','/private/tmp/swiftjli-round5-f4a05be-products/swiftjli-cli','--djpeg','/opt/homebrew/Cellar/jpeg-turbo/'+version+'/bin/djpeg','--matrix',matrix,'--fixtures',fixtures,'--output',str(root/(name+'.json'))]
  item={'name':name,'command':cmd,'startedUTC':now(),'hostLoadBefore':load()};r['commands'].append(item)
  (root/'cli-benchmark-commands.json').write_text(json.dumps(r,indent=2)+'\n')
  with (root/(name+'.log')).open('w') as log:p=subprocess.run(cmd,cwd=repo,stdout=log,stderr=subprocess.STDOUT)
  item.update(exitCode=p.returncode,finishedUTC=now(),hostLoadAfter=load())
  (root/'cli-benchmark-commands.json').write_text(json.dumps(r,indent=2)+'\n')
  print(name,'exit',p.returncode,flush=True)
  if p.returncode:raise SystemExit(p.returncode)
r['status']='complete';(root/'cli-benchmark-commands.json').write_text(json.dumps(r,indent=2)+'\n')
