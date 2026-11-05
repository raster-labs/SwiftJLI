from pathlib import Path
import json,hashlib,statistics,datetime,math
base=Path('/private/tmp/swiftjli-round5-evidence/flat-small-recovery-guards')
def sha(p):
 h=hashlib.sha256()
 with Path(p).open('rb') as f:
  for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
 return h.hexdigest()
def check(row):
 a=row['samplesSeconds'];assert len(a)==20 and all(math.isfinite(x) and x>0 for x in a)
 assert statistics.median(a)==row['medianSeconds'] and sorted(a)[18]==row['p95Seconds']
for kind in ['lossless','dct']:
 folder=base/('native-'+kind+'-1');out=folder/'independent-review.json';assert not out.exists()
 receipt=json.loads((folder/'receipt.json').read_text());reported=json.loads((folder/'summary.json').read_text());assert receipt['status']=='complete'
 raw=[];rawHashes={};order=[]
 if kind=='lossless':
  for batch in receipt['matrix']:
   path=folder/f"receipt-{batch['binary']}-round{batch['round']}.jsonl";rawHashes[str(path)]=sha(path);rows=[json.loads(x) for x in path.read_text().splitlines()];assert rows==batch['records'] and len(rows)==16
   order.append((batch['round'],batch['binary']))
   for row in rows:check(row);assert row['pixelExact'];raw.append({'round':batch['round'],'label':batch['binary'],'case':row['case'],'data':row})
  assert order==[(1,'baseline'),(1,'candidate'),(2,'candidate'),(2,'baseline')]
 else:
  for row in receipt['records']:
   path=folder/f"receipt-{row['round']}-{Path(row['fixture']).stem}-{row['label']}.stdout.json";rawHashes[str(path)]=sha(path);data=json.loads(path.read_text());assert data=={k:v for k,v in row.items() if k not in ['round','label']};check(data)
   raw.append({'round':row['round'],'label':row['label'],'case':row['fixture'],'data':data})
  for case in dict.fromkeys(x['case'] for x in raw):
   for rnd in [1,2]:assert [x['label'] for x in raw if (x['case'],x['round'])==(case,rnd)]==(['baseline','candidate'] if rnd==1 else ['candidate','baseline'])
 cases=list(dict.fromkeys(x['case'] for x in raw));assert len(cases)==(16 if kind=='lossless' else 18)
 rows=[]
 for case in cases:
  differences=[];bm=[];cm=[];pairs=[]
  allvalues=[v['data'] for v in raw if v['case']==case]
  if kind=='lossless':assert len({v['checksum'] for v in allvalues})==1 and all(v['pixelExact'] for v in allvalues)
  else:assert len({(v['outputSHA256'],v['outputBytes']) for v in allvalues})==1
  for rnd in [1,2]:
   selected={x['label']:x['data'] for x in raw if (x['case'],x['round'])==(case,rnd)};assert set(selected)=={'baseline','candidate'}
   b=statistics.median(selected['baseline']['samplesSeconds']);c=statistics.median(selected['candidate']['samplesSeconds']);delta=(c/b-1)*100;differences.append(delta);bm.append(b*1000);cm.append(c*1000);pairs.append({'round':rnd,'baselineMedianMS':b*1000,'candidateMedianMS':c*1000,'percentChange':delta,'baselineP95MS':selected['baseline']['p95Seconds']*1000,'candidateP95MS':selected['candidate']['p95Seconds']*1000})
  expected={'case':case,'roundPercentChange':differences,'repeatedOver5PercentRegression':all(x>5 for x in differences),'baselineMilliseconds':bm,'candidateMilliseconds':cm}
  assert expected==next(x for x in reported['rows'] if x['case']==case)
  rows.append(expected|{'pairs':pairs})
 failures=[x['case'] for x in rows if x['repeatedOver5PercentRegression']];assert failures==reported['repeatedOver5PercentRegressions']
 fixtureRoot=Path(receipt['matrix'][0]['command'][-1]) if kind=='lossless' else Path('/')
 pins={str(Path(k) if Path(k).is_absolute() else fixtureRoot/k):v for k,v in receipt['fixtureSHA256'].items()};pins.update({str(folder/('receipt-'+k)):v for k,v in receipt['binarySHA256'].items()})
 for obj in receipt.get('linkedObjects',receipt.get('objects',{})).values():pins[obj['path']]=obj['sha256']
 for obj in receipt['auxiliaryObjects'].values():pins[obj['path']]=obj['sha256'];pins[obj['modulemap']]=obj['modulemapSHA256']
 for files in receipt['importedArtifacts'].values():pins.update(files)
 harness=receipt.get('harnessPath','/private/tmp/swiftjli-round2-dct-benchmark.swift');pins[harness]=receipt['harnessSHA256'];compiler=receipt.get('compilerPath','/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc');pins[compiler]=receipt['compilerSHA256']
 runner=base/('run-'+kind+'.py');pins[str(runner)]=receipt['runnerSHA256'];pins[str(base/'provenance.py')]=receipt['provenanceSHA256']
 checks={p:sha(p)==h for p,h in pins.items()};assert all(checks.values())
 assert all(v for k,v in receipt.items() if k.endswith('Unchanged'))
 attribution=json.loads((base/'native-build-attribution.json').read_text());assert attribution['sourceRevision']==receipt['candidateRevision'];assert sha(attribution['releaseReceipt'])==attribution['releaseReceiptSHA256'];assert all(sha(p)==h for p,h in attribution['products'].items())
 r={'reviewedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'independent-read-only-verification-passed','candidateRevision':receipt['candidateRevision'],'baselineRevision':receipt['baselineRevision'],'receiptSHA256':sha(folder/'receipt.json'),'reportedSummarySHA256':sha(folder/'summary.json'),'scriptSHA256':sha(__file__),'records':len(raw),'pairs':len(raw)//2,'cases':len(cases),'allRawRowsMatchReceipt':True,'allMediansAndP95Recomputed':True,'allRecordedExactnessChecksPass':True,'allPairedComparisonsAndScreensMatch':True,'processPairOrderingVerified':True,'allPinsStable':True,'pinChecks':checks,'rawSHA256':rawHashes,'buildAttributionVerified':True,'repeatedOver5PercentRegressions':failures,'rows':rows,'qualification':'Original native screen preserved. Lossless ramp19 repeated regression holds candidate; passing DCT and exactness do not waive that failure. No new binary execution, compilation or profiling by this review.'}
 out.write_text(json.dumps(r,indent=2)+'\n');print(kind,len(raw),'records',len(raw)//2,'exactpairs','repeated',failures)
 for x in rows:
  if x['case'] in ['ramp-19','flat-19','flat-12-512.jpg']:print(x['case'],x['roundPercentChange'])
