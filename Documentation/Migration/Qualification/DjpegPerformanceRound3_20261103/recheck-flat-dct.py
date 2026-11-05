import datetime,hashlib,json,subprocess
from pathlib import Path
folder=Path('/private/tmp/swiftjli-round3-evidence/final')
paths={k:folder/('native-dct-'+k) for k in ['baseline','candidate']}
fixture=Path('/private/tmp/swiftjli-round2-dct-coverage/flat-8-512.jpg')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
result={'reason':'Original second candidate round was highly variable (0.684 to 3.785 ms), unlike its first round; targeted follow-up retains original samples without replacement.','startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceRevision':'5351088d3bb4630a32de6509e4d62210ad14aaa0','binarySHA256':{k:sha(p) for k,p in paths.items()},'fixtureSHA256':sha(fixture),'powerBefore':subprocess.check_output(['pmset','-g','batt'],text=True),'records':[]}
for trial in range(4):
 pair={}
 for label in (['baseline','candidate'] if trial%2==0 else ['candidate','baseline']):
  cmd=[str(paths[label]),str(fixture)];r=json.loads(subprocess.check_output(cmd,text=True));pair[label]=r
  result['records'].append({'round':trial+1,'label':label,'command':cmd,**r})
 assert pair['baseline']['outputSHA256']==pair['candidate']['outputSHA256']
 print(trial+1,{k:round(v['medianSeconds']*1000,3) for k,v in pair.items()},flush=True)
result['finishedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat();result['powerAfter']=subprocess.check_output(['pmset','-g','batt'],text=True)
(folder/'flat-dct-follow-up.json').write_text(json.dumps(result,indent=2)+'\n')
