from pathlib import Path
import json,hashlib,copy
root=Path.cwd();e=root/'work/completion-evidence';out=e/'performance-ac';run=json.loads((out/'results.json').read_text());rows=json.loads((out/'per-case-summary.json').read_text());old=json.loads((e/'performance/disposition.json').read_text())
assert run['status']=='passed_execution_identity_and_environment_checks'
assert len(rows)==140
for snapshot in [run['initialPower'],run['finalPower'],*run['powerChecks']]:
 assert "'AC Power'" in snapshot['battery'].splitlines()[0]
 assert snapshot['settings']==run['initialPower']['settings']
for path,digest in run['sourceHashes'].items():assert hashlib.sha256((root/'work/SwiftJLI'/path).read_bytes()).hexdigest()==digest
for path,digest in run['harnessHashes'].items():assert hashlib.sha256((root/'work/completion-benchmark'/path).read_bytes()).hexdigest()==digest
assert hashlib.sha256((root/'work/completion-benchmark-build/out/Products/Release/Benchmark').read_bytes()).hexdigest()==run['binarySHA256']
accepted=[]
for row in rows:
 if row['investigationRequired']:
  if row['size']==19:group='fixed-admission-and-bounded-execution'
  elif row['profile']=='dct12' and row['operation']=='Encode':group='checked-uint12-borrowed-input'
  elif row['size']==512 and row['profile']in ['rgb8','progressiveRGB8']and row['operation']=='Encode':group='bounded-rgb-row-conversion'
  else:raise RuntimeError('Additional unexplained case requires investigation: '+str(row))
  row.update(disposition='accepted_deliberate_safety_correctness_cost',reasonGroup=group,**copy.deepcopy(old['reasonGroups'][group]));accepted.append(row)
 else:row['disposition']='no_repeated_median_increase_over_5_percent_in_these_two_runs'
 row['updatedBaseline']=[{'medianSeconds':x['successorMedianSeconds'],'observedRangeSeconds':x['successorRangeSeconds']}for x in row['runs']]
meta={k:copy.deepcopy(old[k]) for k in ['status','authority','comparisonPredecessor','originalProvenancePin','operationCasesMeasuredTwice','exactOutputComparisons','reasonGroups']}
meta.update(sourceRevision=run['revision'],shippingSourceMatches='e7e54f756cccec07a66870ebefd68b5bbb5c79a6',repeatedOverThreshold=len(accepted),explicitlyAcceptedCases=len(accepted),unexplainedConfirmedCases=0,cases=rows,environment=f"Native ARM64 Swift 6.4 release, stable AC power/settings, {len(run['powerChecks'])} in-run power snapshots plus initial/final snapshots, all case thermal states nominal. No overlapping local codec build/fuzz/trace work. Owner confirmed heavy applications idle. Raw load averages retained.",limitations=['One developer host; no other-device performance inference. AC and battery results are separate measurements, not pooled.','Approximate paired bootstrap intervals describe within-run sampling, not population or multiple-comparison guarantees.','Retained attribution probes were executed during the earlier battery qualification against identical shipping sources. They establish unchanged code-path costs; their private @testable timings are not AC measurements and are not additive to public timings.',*old['limitations'][3:]])
(out/'disposition.json').write_text(json.dumps(meta,indent=2)+'\n')
oldkeys={(r['cohort'],r['size'],r['pattern'],r['profile'],r['operation'])for r in old['cases']if r['investigationRequired']}
print('Accepted cases:',len(accepted),'No repeated crossing:',140-len(accepted))
for group in meta['reasonGroups']:
 subset=[r for r in accepted if r['reasonGroup']==group];runs=[x for r in subset for x in r['runs']]
 print(group,len(subset),'percent range',min(x['changePercent']for x in runs),max(x['changePercent']for x in runs),'microseconds',min(x['absoluteChangeMicroseconds']for x in runs),max(x['absoluteChangeMicroseconds']for x in runs))
for r in accepted:
 key=(r['cohort'],r['size'],r['pattern'],r['profile'],r['operation'])
 if key not in oldkeys:print('Additional AC case:',key)
print('Power checks:',len(run['powerChecks']))
