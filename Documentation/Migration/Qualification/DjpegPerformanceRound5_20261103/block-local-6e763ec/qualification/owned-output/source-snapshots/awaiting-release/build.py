from pathlib import Path
import json,shutil,sys
from provenance import ROOT,sha,now,arguments,write,load_plan,check_after,Commands,record_failure

folder=arguments('build');path=folder/'build.json'
record={'status':'preparing','startedUTC':now(),'commands':[]}
write(path,record)
try:
    plan,expected=load_plan()
    record.update(sourceRevision=plan['sourceRevision'],preparedSHA256=sha(ROOT/'prepared.json'),
        inputSHA256=expected,method=plan['method'])
    snapshot=folder/'source'
    assert not snapshot.exists();snapshot.mkdir()
    for source in plan['sourceSHA256']:
        shutil.copyfile(source,snapshot/Path(source).name)
    shutil.copyfile(ROOT/'prepared.json',snapshot/'prepared.json')
    products=Path(plan['products']);toolchain=Path(plan['toolchain']);turbo=Path(plan['libjpegRoot'])
    binary=folder/'compare';object_file=folder/'jpeg_bench.o'
    assert not binary.exists() and not object_file.exists()
    # Same optimisation, target, library linkage and source order as qualified
    # c-final5f9. Only paths and output artifact locations differ.
    commands=[
        [str(toolchain/'clang'),'-O3','-std=c11','-Wall','-Wextra','-Werror',
         '-target','arm64-apple-macos26.0','-isysroot',plan['sdk'],'-I',str(turbo/'include'),
         '-c',str(ROOT/'jpeg_bench.c'),'-o',str(object_file)],
        [str(toolchain/'swiftc'),str(products/'SwiftJLIEntropyC.o'),'-Xcc',
         '-fmodule-map-file='+plan['modulemap'],'-O','-parse-as-library','-swift-version','6',
         '-strict-concurrency=complete','-target','arm64-apple-macos26.0','-sdk',plan['sdk'],
         '-I',str(products),'-I',str(ROOT),str(products/'SwiftJLI.o'),str(object_file),
         str(turbo/'lib/libjpeg.a'),'-framework','Accelerate',str(ROOT/'Compare.swift'),'-o',str(binary)]
    ]
    record['status']='running';write(path,record)
    runner=Commands(folder,record,path)
    record['compilerVersion']=runner.run([str(toolchain/'swiftc'),'--version']).stdout.decode()
    for command in commands: runner.run(command,timeout=300)
    record['binarySHA256']=sha(binary);record['comparatorCObjectSHA256']=sha(object_file)
    record['loadedLibraries']=runner.run(['/usr/bin/otool','-L',str(binary)]).stdout.decode()
    assert 'libjpeg' not in record['loadedLibraries'].lower(),'Unexpected dynamic libjpeg linkage'
    check_after(record,plan,expected,binary)
    record.update(status='passed',exitCode=0)
except Exception as error:
    record_failure(record,error,folder)
finally:
    record['finishedUTC']=now();write(path,record)
print('build',record['status'],path)
sys.exit(0 if record['status']=='passed' else 1)
