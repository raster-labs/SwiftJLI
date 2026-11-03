"""Derive composed C-row gate results without pooling separate timing methods."""
from pathlib import Path
import datetime,hashlib,json
p=Path(__file__).resolve().parent
load=lambda name:json.loads((p/name).read_text())
t=load('targeted-results.json'); f=load('lossless-same-binaries.json'); d=load('dct.json')
assert t['status']==f['status']==d['status']=='complete'
assert t['binarySHA256']==f['binarySHA256']
assert all(r['exitCode']==0 and r['pixelExact'] for r in t['records'])
assert all(run['exitCode']==0 and all(r['pixelExact'] for r in run['records']) for run in f['matrix'])

def compare(records,key):
 cases=list(dict.fromkeys(r[key] for r in records)); rounds=sorted(set(r['round'] for r in records))
 data={(r['round'],r['label'],r[key]):r for r in records}; output=[]
 for case in cases:
  pairs=[]
  for n in rounds:
   b=data[n,'baseline',case]; c=data[n,'candidate',case]
   if key=='fixture': assert b['outputSHA256']==c['outputSHA256'] and b['outputBytes']==c['outputBytes']
   bm,cm=b['medianSeconds'],c['medianSeconds']
   pairs.append({'round':n,'baselineMedianMS':bm*1000,'candidateMedianMS':cm*1000,'latencyChangePercent':(cm/bm-1)*100})
  output.append({'case':case,'pairs':pairs,'allRoundsOverFivePercentSlower':all(r['latencyChangePercent']>5 for r in pairs)})
 return output
full=[dict(r,round=run['round'],label=run['binary']) for run in f['matrix'] for r in run['records']]
summary={'candidateRevision':t['candidateRevision'],'baselineRevision':t['baselineRevision'],
 'baselineProductionEquivalent':'e0cfea0fa2f702cb558f6896db03501efcd0b463',
 'rowOrigin':'b12f8ce9432975ddf6d271ae144d617d4dbf9216',
 'decision':'Focused correctness and paired performance gate passed; ready for parent integration and new-row safety qualification, which remain pending.',
 'scope':'Original portable C left/Pt0/UInt16 rows for automatic lossless only. Code0 category1...7 specialisation and unchanged generic fallback live in separate C translation units. Explicit private flag replaces the prior added TaskLocal member. Qualified ACBlock.c and NativeExecution.swift remain byte-identical; copied reader helpers retain qualified always_inline attributes.',
 'focusedRelease':{'tests':53,'suites':12,'exitCode':0,'receipt':'tests.json'},
 'targetedGate':{'cases':4,'rounds':4,'pixelExact':True,'records':len(t['records']),'summary':compare(t['records'],'case')},
 'sameBinaryFullLossless':{'cases':16,'rounds':2,'pixelExact':True,'records':len(full),'processExitCodes':[run['exitCode'] for run in f['matrix']], 'sameBinaryHashesAsTargeted':True,'summary':compare(full,'case')},
 'dctControls':{'fixtures':12,'rounds':2,'outputSHA256AndBytesMatch':True,'records':len(d['records']),'exitCode':0,'summary':compare(d['records'],'fixture')},
 'interpretation':[
  'Large ramp targets improve37.4-50.2percent across four immediate pairs; large noise improves50.4-52.9percent. Full lossless with the identical linked binaries confirms ramp512/2048/3072 gains40.6-45.5percent and noise512/2048/3072 gains52.3-53.2percent.',
  'No full lossless or DCT control case has a greater-than5percent regression in either round. Exactness passed every executed record. The earlier b12 control regressions are not reproduced in this composition.',
  'These results do not prove TaskLocal layout alone caused earlier regressions: the composition also retains qualified always_inline reader helpers and the qualified DC+AC base. The evidence supports the combined candidate only.',
  'Timings are provisional shared-host SwiftJLI revision comparisons. No djpeg, cross-platform, RSS or final integrated acceptance claim is made.'
 ],
 'qualityAndLifetime':[
  'Independent source review found no remaining production defect; scoped raw input/output borrows stay on the caller, C performs no allocation/thread/I/O, and input/output aliasing is permitted. Metadata/state/result are separately scoped.',
  'Native malformed category, truncation, marker, prefix/offset, cursor, modulo, max width, odd typed output, restart and cancellation cases passed. Public explicit scalar retains Swift and reports scalarCPU; automatic C rows report the same backend.',
  'Corrected public failure-stage test uses an admitted table and truncation after five samples, then requires one provider borrow, one abort, no seal and exact partial output. Prior category17 public fixture did not prove row entry; see the retained clarification receipt.',
  'Fixed1048-byte scan metadata fits the existing1MiB reserve; no new frame buffer, heap allocation in C or limit increase. Source-level bound is not measured RSS.',
  'No public API, fidelity, sample interpretation or tolerance change. Five warmups plus20 samples; exact checking outside timing.'
 ],
 'unexecuted':['New composed-row ASan/UBSan corpus','Integrated full Release/ASan/TSan','RSS','CLI and independent codec oracle','Other platforms/toolchains'],
 'sourceProvenance':{'initial':'source.json is retained initial source-only status, superseded by this completed gate receipt.', 'baseline':'baseline-products.json pins copied qualified281/e0 Release modules, objects and C module map.', 'equivalence':'source-equivalence.json proves unchanged ACBlock.c/NativeExecution.swift and exact copied helpers; does not assert emitted Swift object identity.', 'host':'targeted-host.jsonl and full-existing-host.jsonl retain process snapshots; DCT runner retains raw samples but did not collect per-case host snapshots.', 'methods':'Four fresh per-case pairs and two full sequences remain separate; full lossless reuses targeted executables byte-for-byte.'},
 'finishedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat()}
for key in ['sameBinaryFullLossless','dctControls']:
 assert all(pair['latencyChangePercent']<=5 for row in summary[key]['summary'] for pair in row['pairs'])
(p/'decision.json').write_text(json.dumps(summary,indent=2)+'\n')
files=[v for v in sorted(p.iterdir()) if v.is_file() and v.suffix in ['.json','.jsonl','.py','.swift','.log','.patch','.txt','.md'] and v.name!='index.json']
index={'status':'Completed composed-row correctness/performance gate; integration and new-path sanitizers/RSS remain pending.', 'sourcePin':t['candidateRevision'],'files':[{'path':str(v),'bytes':v.stat().st_size,'sha256':hashlib.sha256(v.read_bytes()).hexdigest()} for v in files], 'excluded':'Generated binaries/build products/fixtures are excluded; binary and object hashes remain in raw receipts.'}
(p/'index.json').write_text(json.dumps(index,indent=2)+'\n')
for key in ['targetedGate','sameBinaryFullLossless','dctControls']:
 print(key)
 for row in summary[key]['summary']:
  print(row['case'],[round(r['latencyChangePercent'],2) for r in row['pairs']], [round(r['candidateMedianMS'],4) for r in row['pairs']])
print('Indexed',len(files),'text files')
