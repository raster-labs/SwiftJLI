import datetime, hashlib, json, statistics, subprocess
from pathlib import Path
out = Path(__file__).parent
root = Path('/private/tmp/swiftjli-round5-lossless-audit')
products = Path('/private/tmp/swiftjli-round5-lossless-build/out/Products/Release')
compiler = Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
sdk = Path('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk')
harness = Path('/private/tmp/swiftjli-native-matrix.swift')
fixtures = Path('/private/tmp/swiftjli-native-matrix-fixtures')
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def read(command): return subprocess.check_output(command, text=True).strip()
prior = json.loads(Path('/private/tmp/swiftjli-round5-evidence/combined-prefill/native.json').read_text())
binaries = {
    'round4': Path('/private/tmp/swiftjli-round5-evidence/combined-prefill/native-baseline'),
    'round5_0d56': Path('/private/tmp/swiftjli-round5-evidence/combined-prefill/native-candidate'),
    'specialised': out/'native-specialised',
}
assert sha(binaries['round4']) == prior['binarySHA256']['baseline']
assert sha(binaries['round5_0d56']) == prior['binarySHA256']['candidate']
assert sha(harness) == prior['harnessSHA256']
assert sha(compiler) == prior['compilerSHA256']
revision = read(['git','-C',str(root),'rev-parse','HEAD'])
assert not read(['git','-C',str(root),'status','--porcelain'])
obj = products/'SwiftJLI.o'
object_hash = sha(obj)
command = [str(compiler),'-O','-parse-as-library','-target','arm64-apple-macos26.0','-sdk',str(sdk),'-I',str(products),str(obj),'-framework','Accelerate',str(harness),'-o',str(binaries['specialised'])]
with (out/'compile.log').open('w') as stream: subprocess.run(command,check=True,stdout=stream,stderr=subprocess.STDOUT)
assert sha(obj) == object_hash
result = {
    'status':'running','startedUTC':now(),'timingStatus':'provisional: unrelated host workloads',
    'revisions':{'round4':prior['baselineRevision'],'round5_0d56':prior['candidateRevision'],'specialised':revision},
    'method':prior['method']+' Three binaries run in reversed order across two rounds; all original samples retained.',
    'compilerSHA256':sha(compiler),'compilerVersion':read([str(compiler),'--version']),
    'harnessPath':str(harness),'harnessSHA256':sha(harness),'runnerSHA256':sha(__file__),
    'fixtureSHA256':{p.name:sha(p) for p in sorted(fixtures.glob('*'))},
    'binarySHA256':{name:sha(path) for name,path in binaries.items()},
    'linkedObjects':{'round4':prior['linkedObjects']['baseline'],'round5_0d56':prior['linkedObjects']['candidate'],'specialised':{'path':str(obj),'sha256':object_hash}},
    'compileCommand':command,'matrix':[],
}
path=out/'native.json'
def save(): path.write_text(json.dumps(result,indent=2)+'\n')
save()
for round_number,order in enumerate([list(binaries),list(reversed(binaries))],1):
    for name in order:
        (out/f'processes-{name}-round{round_number}.txt').write_text(read(['ps','-axo','pid,pcpu,comm']))
        command=[str(binaries[name]),'benchmark',str(fixtures)]
        with (out/f'native-{name}-round{round_number}.jsonl').open('w') as stream:
            subprocess.run(command,check=True,stdout=stream)
        records=[json.loads(line) for line in (out/f'native-{name}-round{round_number}.jsonl').read_text().splitlines()]
        assert len(records)==16 and all(r['pixelExact'] and len(r['samplesSeconds'])==20 for r in records)
        result['matrix'].append({'round':round_number,'binary':name,'command':command,'records':records})
        save()
        print('Completed',name,'round',round_number,'16 exact cases',flush=True)
for name,binary in binaries.items(): assert sha(binary)==result['binarySHA256'][name]
assert sha(compiler)==result['compilerSHA256']
assert sha(harness)==result['harnessSHA256']
result['status']='complete';result['finishedUTC']=now();save()
for case in [r['case'] for r in result['matrix'][0]['records']]:
    medians={name:[next(r['medianSeconds'] for r in row['records'] if r['case']==case) for row in result['matrix'] if row['binary']==name] for name in binaries}
    ratios={name:[100*(c/b-1) for c,b in zip(medians['specialised'],medians[name])] for name in ['round4','round5_0d56']}
    print(case, 'medians-ms', {k:[round(v*1000,6) for v in vs] for k,vs in medians.items()},'changes-%',ratios,flush=True)
