from pathlib import Path
import json,hashlib,statistics,datetime,math
base=Path(__file__).resolve().parent;out=base/'run1/independent-review.json';assert not out.exists()
plan=json.loads((base/'plan.json').read_text());r=json.loads((base/'run1/receipt.json').read_text());spec=plan['kinds']['lossless'];originalPath=Path(spec['originalReceipt']);original=json.loads(originalPath.read_text())
def sha(p):
 h=hashlib.sha256()
 with Path(p).open('rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()
def sample(row):
 x=row['samplesSeconds'];assert len(x)==20 and all(math.isfinite(t) and t>0 for t in x)
 assert statistics.median(x)==row['medianSeconds'] and sorted(x)[18]==row['p95Seconds']
 assert row['pixelExact'] and row['checksum']==spec['expectedCases'][row['case']]
checks={p:sha(p)==h for p,h in r['pinnedInputs'].items()};assert all(checks.values()) and all(r['identityChecks'].values());assert r['planSHA256']==sha(base/'plan.json')
expected=[]
for step in plan['schedule']:
 for label in step['binaryOrder']:expected.append((step['round'],label,step['binaryOrder'],[spec['binaries'][label]['path'],'benchmark',spec['fixtureRoot']]))
assert len(expected)==12 and len(r['processes'])==12
assert [(x['round'],x['label'],x['binaryOrder'],x['command']) for x in r['processes']]==expected
assert sum(step['binaryOrder'][0]=='baseline' for step in plan['schedule'])==3
raw=[];rawHashes={};originalRows=[];originalCases=[x['case'] for x in original['matrix'][0]['records']]
for proc in r['processes']:
 assert proc['exitCode']==0;stdout=Path(proc['stdout']);rawHashes[str(stdout)]=sha(stdout);rawHashes[proc['stderr']]=sha(proc['stderr']);rows=[json.loads(s) for s in stdout.read_text().splitlines()];assert len(rows)==16 and [x['case'] for x in rows]==originalCases
 for row in rows:sample(row);raw.append({k:proc[k] for k in ['kind','round','label','binaryOrder']}|{'result':row})
assert raw==r['records'] and len(raw)==192
for batch in original['matrix']:
 p=originalPath.parent/f"receipt-{batch['binary']}-round{batch['round']}.jsonl";rawHashes[str(p)]=sha(p);rows=[json.loads(x) for x in p.read_text().splitlines()];assert rows==batch['records']
 for row in rows:sample(row);originalRows.append({'round':batch['round'],'label':batch['binary'],'result':row})
def summary(pairs):
 v=[p['percentChange'] for p in pairs]
 return {'medianPairedPercentChange':statistics.median(v),'rangePercentChange':[min(v),max(v)],'roundsOver5Percent':sum(x>5 for x in v),'allRoundsOver5Percent':all(x>5 for x in v),'orderStrataMedianPercentChange':{label:statistics.median(p['percentChange'] for p in pairs if p['baselineFirst']==flag) for label,flag in [('baselineFirst',True),('candidateFirst',False)]}}
analyses=[]
for case in spec['selectedCases']:
 pairs=[]
 for phase,rows,rounds in [('original',originalRows,2),('diagnostic',raw,6)]:
  for rnd in range(1,rounds+1):
   selected=[x for x in rows if x['round']==rnd and x['result']['case']==case];assert len(selected)==2
   v={x['label']:statistics.median(x['result']['samplesSeconds']) for x in selected};assert set(v)=={'baseline','candidate'};b=v['baseline'];c=v['candidate'];assert len({x['result']['checksum'] for x in selected})==1
   pairs.append({'phase':phase,'round':rnd,'baselineFirst':selected[0]['label']=='baseline','baselineMicroseconds':b*1e6,'candidateMicroseconds':c*1e6,'changeMicroseconds':(c-b)*1e6,'percentChange':(c/b-1)*100})
 analyses.append({'kind':'lossless','case':case,'pairs':pairs,'originalTwo':summary(pairs[:2]),'diagnosticSix':summary(pairs[2:]),'combinedEightDescriptiveOnly':summary(pairs)})
assert analyses==r['analysis'] and r['status']=='complete-diagnostic-only' and r['originalAcceptanceGate']=='held-and-preserved'
review={'reviewedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'independent-read-only-verification-passed','receiptSHA256':sha(base/'run1/receipt.json'),'scriptSHA256':sha(__file__),'processes':12,'rawDiagnosticRecords':192,'originalRecordsReverified':64,'allRawRowsEqualReceipt':True,'allSampleMediansP95Recomputed':True,'allRecordedFullOutputExactChecksPass':True,'sameFrozenBinariesAndFixtures':True,'complete16CaseOrderPreserved':True,'sixRoundBinaryOrderVerified':True,'allEightPairValuesAndOrderStrataMatch':True,'pinChecks':checks,'rawSHA256':rawHashes,'analysis':analyses,'interpretation':'The six additional diagnostic ramp19 pairs have0/6 above5%, but the original two failed pairs remain in the combined eight. Descriptive combined median is negative with2/8 above5%. Fixed-binary variability does not establish causation or automatically waive the original primary regression gate. Per-process medians remain the paired units; all raw rows retained. No new compilation, disassembly, profiling or binary execution was performed by this review.'}
out.write_text(json.dumps(review,indent=2)+'\n');print(out)
a=next(x for x in analyses if x['case']=='ramp-19');print(json.dumps(a,indent=2))
