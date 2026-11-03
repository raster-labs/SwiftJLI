import json,re,subprocess,sys
from pathlib import Path
from provenance import ROOT,sha,now,arguments,write,load_plan,check_after,host_load,Commands,record_failure

folder=arguments('results');path=folder/'results.json'
result={'status':'preparing','startedUTC':now(),'records':[],'excluded':[],'memory':[],'commands':[]}
write(path,result)
try:
    plan,expected=load_plan()
    binary=folder/'compare';build=json.loads((folder/'build.json').read_text())
    assert build['status']=='passed' and build['exitCode']==0
    assert build['preparedSHA256']==sha(ROOT/'prepared.json') and build['inputSHA256']==expected
    assert sha(binary)==build['binarySHA256'],'Build/runtime binary drift'
    assert sha(folder/'jpeg_bench.o')==build['comparatorCObjectSHA256'],'Comparator object drift'
    result.update(sourceRevision=plan['sourceRevision'],preparedSHA256=build['preparedSHA256'],
        buildReceiptSHA256=sha(folder/'build.json'),inputSHA256=expected,
        binarySHA256=sha(binary),method=plan['method'],fixtureSHA256=plan['fixtureSHA256'],
        hostLoadBefore=host_load(),powerBefore=subprocess.check_output(['pmset','-g','batt'],text=True,timeout=10))
    result['status']='running';write(path,result)
    runner=Commands(folder,result,path)
    cases=[(Path(c['fixture']),c['workers'],c['tolerance']) for c in plan['cases']]
    expected_status={(c['fixture'],c['workers'],c['tolerance']):c['expectedStatus'] for c in plan['cases']}
    errors=runner.run([str(binary),'errors',str(cases[0][0]),'8','0','1'])
    result['containedErrorCheck']=json.loads(errors.stdout)
    assert result['containedErrorCheck']['containedCErrors']==4
    accepted={};quality_by_case={}
    for round_number in [1,2]:
        for fixture,workers,tolerance in cases:
            process=runner.run([str(binary),'timing',str(fixture),str(workers),str(tolerance),str(round_number)])
            record=json.loads(process.stdout);record['hostLoadAfter']=host_load()
            assert record['fixture']==fixture.name and record['workerCeiling']==workers and record['tolerance']==tolerance
            assert record['status'] in ['quality-excluded','passed']
            assert (record['maximumSampleDifference']<=tolerance)==(record['status']=='passed')
            key=(str(fixture),workers,tolerance)
            assert record['status']==expected_status[key],'Named case quality disposition changed'
            identity={k:record[k] for k in ['status','maximumSampleDifference','outputBytes','storageBits',
                'meaningfulBits','components','swiftFNV1a64','turboFNV1a64']}
            if key in quality_by_case: assert identity==quality_by_case[key],'Quality disposition/output changed between rounds'
            else: quality_by_case[key]=identity
            if record['status']=='quality-excluded': result['excluded'].append(record)
            else:
                assert len(record['swift']['samplesSeconds'])==20 and len(record['turbo']['samplesSeconds'])==20
                result['records'].append(record);accepted[key]=record
            write(path,result)
            print(round_number,fixture.name,workers,record['status'],record['maximumSampleDifference'],
                *(f'{name}={record[name]["medianSeconds"]*1000:.4f}ms' for name in ['swift','turbo'] if name in record),flush=True)
    assert len(accepted)==12 and len(result['records'])==24 and len(result['excluded'])==8,'Expected12 admitted and4 excluded cases per round'
    rss_pattern=re.compile(rb'\n\s*(\d+)\s+maximum resident set size')
    for trial in [1,2,3]:
        for (fixture,workers,tolerance),quality in accepted.items():
            for engine in (['swift','turbo'] if trial%2 else ['turbo','swift']):
                process=runner.run(['/usr/bin/time','-l',str(binary),'memory-'+engine,
                    fixture,str(workers),str(tolerance),str(trial)])
                memory=json.loads(process.stdout);match=rss_pattern.search(process.stderr)
                assert match,repr(process.stderr)
                assert memory['outputBytes']==quality['outputBytes']
                assert memory['outputFNV1a64']==quality[engine+'FNV1a64']
                memory.update(trial=trial,maximumRSSBytes=int(match[1]))
                result['memory'].append(memory);write(path,result)
    assert len(result['memory'])==72
    check_after(result,plan,expected,binary)
    result.update(status='passed',exitCode=0,hostLoadAfter=host_load(),
        powerAfter=subprocess.check_output(['pmset','-g','batt'],text=True,timeout=10))
except Exception as error:
    record_failure(result,error,folder)
finally:
    result['finishedUTC']=now();write(path,result)
print('owned-output',result['status'],path,flush=True)
sys.exit(0 if result['status']=='passed' else 1)
