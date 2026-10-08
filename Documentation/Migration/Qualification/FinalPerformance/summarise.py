from pathlib import Path
import json, random, statistics
root=Path(__file__).resolve().parent
runs=[]
for i in [1,2]:
 rows=[json.loads(s) for s in (root/f'public-extended-{i}.jsonl').read_text().splitlines()]
 assert rows[-1]['event']=='complete'
 cases=[x for x in rows if x.get('event')=='case'];assert len(cases)==60
 assert all(x['codestreamsEqual'] and x['samplesEqual'] and x['warmups']==5 and x['timedIterations']==20 for x in cases)
 runs.append({(x['width'],x['pattern'],x['profile']):x for x in cases})
summary=[]
for key in sorted(runs[0]):
 for op in ['Encode','Decode']:
  samples=[]
  for run in runs:
   x=run[key];a=x['predecessor'+op];b=x['successor'+op]
   rng=random.Random(6410)
   aa=a['samplesSeconds'];bb=b['samplesSeconds'];assert len(aa)==len(bb)==20
   ratios=[]
   for _ in range(1000):
    indices=[rng.randrange(20) for _ in range(20)]
    ratios.append(100*(statistics.median([bb[j] for j in indices])/statistics.median([aa[j] for j in indices])-1))
   ratios.sort()
   samples.append({'pairedBootstrap95PercentInterval':[ratios[24],ratios[974]],'predecessorMedianSeconds':a['medianSeconds'],'successorMedianSeconds':b['medianSeconds'],
     'changePercent':100*(b['medianSeconds']/a['medianSeconds']-1),
     'absoluteChangeMicroseconds':1e6*(b['medianSeconds']-a['medianSeconds']),
     'predecessorRangeSeconds':[a['minimumSeconds'],a['maximumSeconds']],
     'successorRangeSeconds':[b['minimumSeconds'],b['maximumSeconds']],
     'thermalBefore':x['before']['thermalState'],'thermalAfter':x['after']['thermalState']})
  summary.append({'size':key[0],'pattern':key[1],'profile':key[2],'operation':op,'runs':samples,'investigationRequired':all(x['changePercent']>5 for x in samples)})
(root/'per-case-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
flags=[x for x in summary if x['investigationRequired']]
print('120 exact-output comparisons; two runs of each 60-case matrix.')
print('Repeated >5% latency increases:',len(flags))
for x in flags:print(x['size'],x['pattern'],x['profile'],x['operation'],[(round(y['changePercent'],1),round(y['absoluteChangeMicroseconds'],1)) for y in x['runs']])
