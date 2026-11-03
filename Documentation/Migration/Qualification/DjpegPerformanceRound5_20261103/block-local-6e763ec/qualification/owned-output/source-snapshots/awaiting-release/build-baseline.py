from pathlib import Path
import json,sys
from provenance import ROOT,sha,now,arguments,write,load_plan,check_after,Commands,record_failure

folder=arguments('baseline-build');path=folder/'baseline-build.json'
record={'status':'preparing','startedUTC':now(),'commands':[]}
write(path,record)
try:
    plan,expected=load_plan();candidate=json.loads((folder/'build.json').read_text())
    assert candidate['status']=='passed' and candidate['preparedSHA256']==sha(ROOT/'prepared.json')
    assert candidate['inputSHA256']==expected
    object_file=folder/'jpeg_bench.o'
    assert sha(object_file)==candidate['comparatorCObjectSHA256'],'Shared comparator object drift'
    record.update(sourceRevision=plan['baseline']['sourceRevision'],preparedSHA256=sha(ROOT/'prepared.json'),
        inputSHA256=expected,candidateBuildReceiptSHA256=sha(folder/'build.json'),
        comparatorCObjectSHA256=sha(object_file),method='RSS-only baseline companion; same unchanged Compare/C source and exact same comparator C object as current candidate')
    baseline=plan['baseline'];products=Path(baseline['products']);binary=folder/'compare-ca0'
    assert not binary.exists()
    command=[str(Path(plan['toolchain'])/'swiftc'),str(products/'SwiftJLIEntropyC.o'),'-Xcc',
        '-fmodule-map-file='+baseline['modulemap'],'-O','-parse-as-library','-swift-version','6',
        '-strict-concurrency=complete','-target','arm64-apple-macos26.0','-sdk',plan['sdk'],
        '-I',str(products),'-I',str(ROOT),str(products/'SwiftJLI.o'),str(object_file),
        str(Path(plan['libjpegRoot'])/'lib/libjpeg.a'),'-framework','Accelerate',str(ROOT/'Compare.swift'),'-o',str(binary)]
    record['status']='running';write(path,record)
    runner=Commands(folder,record,path);runner.run(command,timeout=300)
    record['binarySHA256']=sha(binary)
    record['loadedLibraries']=runner.run(['/usr/bin/otool','-L',str(binary)]).stdout.decode()
    assert 'libjpeg' not in record['loadedLibraries'].lower()
    check_after(record,plan,expected,binary)
    record.update(status='passed',exitCode=0)
except Exception as error: record_failure(record,error,folder)
finally:
    record['finishedUTC']=now();write(path,record)
print('baseline-build',record['status'],path)
sys.exit(0 if record['status']=='passed' else 1)
