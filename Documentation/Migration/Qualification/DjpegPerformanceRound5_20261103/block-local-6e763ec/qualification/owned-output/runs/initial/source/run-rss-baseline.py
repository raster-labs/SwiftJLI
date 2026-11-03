import json,re,subprocess,sys
from pathlib import Path
from provenance import ROOT,sha,now,arguments,write,load_plan,check_after,host_load,Commands,record_failure

folder=arguments('baseline-rss');path=folder/'baseline-rss.json'
record={'status':'preparing','startedUTC':now(),'commands':[],'memory':[]}
write(path,record)
try:
    plan,expected=load_plan()
    candidate_build=json.loads((folder/'build.json').read_text())
    baseline_build=json.loads((folder/'baseline-build.json').read_text())
    qualities=json.loads((folder/'results.json').read_text())
    for receipt in [candidate_build,baseline_build,qualities]:
        assert receipt['status']=='passed' and receipt['preparedSHA256']==sha(ROOT/'prepared.json')
        assert receipt['inputSHA256']==expected
    binaries={'baseline':folder/'compare-ca0','candidate':folder/'compare'}
    binary_hashes={name:sha(binary) for name,binary in binaries.items()}
    assert binary_hashes['baseline']==baseline_build['binarySHA256']
    assert binary_hashes['candidate']==candidate_build['binarySHA256']==qualities['binarySHA256']
    assert sha(folder/'jpeg_bench.o')==candidate_build['comparatorCObjectSHA256']==baseline_build['comparatorCObjectSHA256']
    record.update(sourceRevisions={'baseline':plan['baseline']['sourceRevision'],'candidate':plan['sourceRevision']},
        preparedSHA256=sha(ROOT/'prepared.json'),inputSHA256=expected,
        inputReceipts={str(folder/name):sha(folder/name) for name in ['build.json','baseline-build.json','results.json']},
        binarySHA256=binary_hashes,hostLoadBefore=host_load(),
        method='RSS-only fresh baseline/candidate pairs; unchanged memory-swift mode in the qualified Compare harness.3 trials,12 admitted cases,alternate pair order. Compressed input plus one full output retained. Output byte count and full-output FNV checked against current fixed-quality comparison; no new baseline timings or full sample comparison inside RSS processes.')
    quality={}
    for row in qualities['records']:
        key=(row['fixture'],row['workerCeiling'],row['tolerance'])
        value=(row['outputBytes'],row['swiftFNV1a64'])
        if key in quality: assert quality[key]==value
        quality[key]=value
    cases=[case for case in plan['cases'] if (Path(case['fixture']).name,case['workers'],case['tolerance']) in quality]
    assert len(cases)==12
    runner=Commands(folder,record,path);record['status']='running';write(path,record)
    rss_pattern=re.compile(rb'\n\s*(\d+)\s+maximum resident set size')
    for trial in [1,2,3]:
        for case in cases:
            fixture=Path(case['fixture']);workers=case['workers'];tolerance=case['tolerance']
            size,fnv=quality[(fixture.name,workers,tolerance)]
            for label in (['baseline','candidate'] if trial%2 else ['candidate','baseline']):
                process=runner.run(['/usr/bin/time','-l',str(binaries[label]),'memory-swift',
                    str(fixture),str(workers),str(tolerance),str(trial)])
                value=json.loads(process.stdout);match=rss_pattern.search(process.stderr)
                assert match,repr(process.stderr)
                assert value['fixture']==fixture.name and value['workerCeiling']==workers
                assert value['outputBytes']==size and value['outputFNV1a64']==fnv,'Baseline/candidate output identity mismatch'
                value.update(variant=label,trial=trial,maximumRSSBytes=int(match[1]))
                record['memory'].append(value);write(path,record)
    assert len(record['memory'])==72
    check_after(record,plan,expected)
    record['binariesUnchanged']=all(sha(binary)==binary_hashes[name] for name,binary in binaries.items())
    record['inputReceiptsUnchanged']=all(sha(p)==v for p,v in record['inputReceipts'].items())
    assert record['binariesUnchanged'] and record['inputReceiptsUnchanged']
    record.update(status='passed',exitCode=0,hostLoadAfter=host_load())
except Exception as error: record_failure(record,error,folder)
finally:
    record['finishedUTC']=now();write(path,record)
print('baseline-rss',record['status'],path)
sys.exit(0 if record['status']=='passed' else 1)
