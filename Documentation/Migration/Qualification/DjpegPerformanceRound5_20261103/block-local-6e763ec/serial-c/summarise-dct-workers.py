from pathlib import Path
import hashlib,json,statistics,datetime
root=Path(__file__).resolve().parent;folder=root/'native-dct-workers-1';r=json.loads((folder/'receipt.json').read_text());historicalPath=Path('/private/tmp/swiftjli-round5-evidence/c-row-serial-isolated/dct-workers.json');old=json.loads(historicalPath.read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert r['status']=='complete' and len(r['records'])==96 and len(r['processes'])==96
assert r['fixtureSHA256']==old['fixtureSHA256']
raw=[]
for proc in r['processes']:
 assert proc['exitCode']==0 and sha(proc['stdout'])==proc['stdoutSHA256'] and sha(proc['stderr'])==proc['stderrSHA256']
 v=json.loads(Path(proc['stdout']).read_text());assert len(v['samplesSeconds'])==20
 assert statistics.median(v['samplesSeconds'])==v['medianSeconds'] and sorted(v['samplesSeconds'])[18]==v['p95Seconds']
 assert (v['fixture'],v['maximumWorkers'])==(proc['fixture'],proc['maximumWorkers'])
 raw.append({'round':proc['round'],'label':proc['label'],**v})
assert raw==r['records']
assert [(v['round'],v['fixture'],v['maximumWorkers'],v['label']) for v in raw]==[(v['round'],v['fixture'],v['maximumWorkers'],v['label']) for v in old['records']]
cases=list(dict.fromkeys(v['fixture'] for v in raw));summary=[]
for case in cases:
 assert len({(v['outputSHA256'],v['outputBytes']) for v in raw+old['records'] if v['fixture']==case})==1
 for workers in [1,8]:
  pairs=[]
  for rnd in [1,2]:
   group={v['label']:v for v in raw if (v['fixture'],v['maximumWorkers'],v['round'])==(case,workers,rnd)}
   assert set(group)=={'baseline','candidate'}
   b=statistics.median(group['baseline']['samplesSeconds']);c=statistics.median(group['candidate']['samplesSeconds'])
   pairs.append({'round':rnd,'baselineMedianMS':b*1000,'candidateMedianMS':c*1000,'latencyChangePercent':(c/b-1)*100,'baselineP95MS':group['baseline']['p95Seconds']*1000,'candidateP95MS':group['candidate']['p95Seconds']*1000})
  summary.append({'fixture':case,'maximumWorkers':workers,'pairs':pairs,'bothRoundsOverFivePercentSlower':all(p['latencyChangePercent']>5 for p in pairs)})
checks={p:sha(p)==h for p,h in {**r['sourceSHA256'],**r['originSHA256'],**r['frozenSHA256'],**r['fixtureSHA256']}.items()};assert all(checks.values()) and all(r['identityChecks'].values())
assert sha(root/'run-dct-workers.py')==r['runnerSHA256'] and sha(root/'dct-workers.swift')==r['harnessSHA256']
assert all(sha(folder/('dct-'+k))==v for k,v in r['binarySHA256'].items())
report={'reviewedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'baselineRevision':r['baselineRevision'],'candidateRevision':r['candidateRevision'],'receiptSHA256':sha(folder/'receipt.json'),'historicalWorkloadReceiptSHA256':sha(historicalPath),'summaryScriptSHA256':sha(__file__),'recordCount':96,'pairCount':48,'fixtureWorkerCases':24,'allRawRowsMatchReceipt':True,'allRawMediansP95Recomputed':True,'sameHistoricalCaseWorkerRevisionOrder':True,'sameHistoricalFixtureHashes':True,'allOutputIdentitiesMatchBothRevisionsWorkersRoundsAndHistorical5f9A81':True,'allSourceArtifactFixturePinsStable':True,'summary':summary,'repeatedOver5PercentCases':[s for s in summary if s['bothRoundsOverFivePercentSlower']],'singleRoundOver5Percent':[{'fixture':s['fixture'],'maximumWorkers':s['maximumWorkers'],**p} for s in summary for p in s['pairs'] if p['latencyChangePercent']>5],'qualification':'Serial-helper delta only. The two-round repeated>5% screen passes for these24fixture/worker combinations; small timing outliers retained. This does not qualify either unselected parent/child, waive previous failures, replace lossless/sanitizer/RSS/CLI/external-oracle gates or establish a djpeg win. Shared-host process medians are paired units; no pooled decode-sample independence claim.'}
out=folder/'summary.json';assert not out.exists();out.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'summary':str(out),'repeatedFailures':report['repeatedOver5PercentCases'],'singleRoundOver5Percent':report['singleRoundOver5Percent'],'worker1DCTAndNoise':[s for s in summary if s['maximumWorkers']==1 and s['fixture'] in ['dct12-512.jpg','dct12-2048.jpg','noise-8-512.jpg','noise-12-512.jpg']]},indent=2))
