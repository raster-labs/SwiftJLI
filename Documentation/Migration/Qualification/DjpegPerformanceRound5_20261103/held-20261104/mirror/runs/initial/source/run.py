"""Standalone prototype runner; do not execute without the parent's CPU grant."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,re,subprocess

root=Path(__file__).resolve().parent
sha=lambda path:hashlib.sha256(Path(path).read_bytes()).hexdigest()
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
parser=argparse.ArgumentParser()
parser.add_argument('action',choices=['build','correctness','timing'])
parser.add_argument('--run-name',required=True)
parser.add_argument('--cpu-grant',action='store_true',help='Explicit acknowledgement of the parent-granted CPU slot')
args=parser.parse_args()
assert args.cpu_grant,'No execution without an explicit parent CPU grant'
assert re.fullmatch(r'[a-z0-9][a-z0-9_-]*',args.run_name)
folder=root/'runs'/args.run_name
folder.mkdir(parents=True,exist_ok=True)
output=folder/(args.action+'.json')
assert not output.exists(),'Refusing to overwrite an earlier receipt'
receipt=json.loads((root/'source-receipt.json').read_text())
inputs={**receipt['sourceFiles'],**receipt['referenceArtifacts']}
assert all(sha(path)==digest for path,digest in inputs.items()),'Pinned source/reference drift'
assert all(sha(path)==digest for path,digest in receipt['fixtureSHA256'].items()),'Fixture drift'
compiler=Path(receipt['compiler'])
assert sha(compiler)==receipt['compilerSHA256'],'Compiler drift'
binary=folder/'mirror-probe'
record={'status':'preparing','action':args.action,'startedUTC':now(),
    'sourceReceiptSHA256':sha(root/'source-receipt.json'),'inputSHA256':inputs,
    'fixtureSHA256':receipt['fixtureSHA256'],'compilerSHA256':sha(compiler),
    'referenceRevision':receipt['referenceRevision'],
    'scope':'Standalone integer transform prototype. Frozen ba277 reference remains an unaccepted production candidate.',
    'hostLoadBefore':os.getloadavg()}
if args.action=='build':
    products=Path(receipt['products'])
    command=[str(compiler),'-O','-whole-module-optimization','-parse-as-library',
        '-swift-version','6','-strict-concurrency=complete','-target','arm64-apple-macos26.0',
        '-sdk',receipt['sdk'],'-I',str(products),str(products/'SwiftJLI.o'),
        str(products/'SwiftJLIEntropyC.o'),'-Xcc','-fmodule-map-file='+receipt['modulemap'],
        '-framework','Accelerate',str(root/'CertifiedMirror.swift'),str(root/'Probe.swift'),
        '-o',str(binary)]
else:
    build=json.loads((folder/'build.json').read_text())
    assert build['status']=='complete' and build['exitCode']==0
    assert sha(binary)==build['binarySHA256'],'Prototype binary drift'
    identity_keys=['sourceReceiptSHA256','inputSHA256','fixtureSHA256','compilerSHA256','referenceRevision']
    assert all(build[key]==record[key] for key in identity_keys),'Build/current identity mismatch'
    if args.action=='timing':
        correctness=json.loads((folder/'correctness.json').read_text())
        assert correctness['status']=='complete' and correctness['exitCode']==0
        assert correctness['binarySHA256']==sha(binary)
        assert all(correctness[key]==record[key] for key in identity_keys),'Correctness/current identity mismatch'
    command=[str(binary),'--mode',args.action]
    for fixture in receipt['fixtureSHA256']:command += ['--fixture',fixture]
record['command']=command
record['status']='running'
output.write_text(json.dumps(record,indent=2)+'\n')
with (folder/(args.action+'-host.txt')).open('w') as stream:
    subprocess.run(['ps','-axo','pid,pcpu,comm'],stdout=stream,check=True)
run=subprocess.run(command,capture_output=True,text=True)
(folder/(args.action+'.stdout.txt')).write_text(run.stdout)
(folder/(args.action+'.stderr.txt')).write_text(run.stderr)
record['exitCode']=run.returncode
record['inputsUnchanged']=all(sha(path)==digest for path,digest in inputs.items())
record['fixturesUnchanged']=all(sha(path)==digest for path,digest in receipt['fixtureSHA256'].items())
record['compilerUnchanged']=sha(compiler)==receipt['compilerSHA256']
record['hostLoadAfter']=os.getloadavg();record['finishedUTC']=now()
record['binaryPresent']=binary.is_file()
if binary.exists():record['binarySHA256']=sha(binary)
record['binaryUnchanged']=args.action=='build' or record.get('binarySHA256')==build['binarySHA256']
if args.action!='build' and run.returncode==0:
    record['result']=json.loads(run.stdout)
    assert record['result']['mode']==args.action
record['status']='complete' if run.returncode==0 and all(record[k] for k in ['inputsUnchanged','fixturesUnchanged','compilerUnchanged','binaryUnchanged','binaryPresent']) else 'failed'
output.write_text(json.dumps(record,indent=2)+'\n')
run.check_returncode()
assert record['status']=='complete','Post-run identity verification failed'
print(args.action,record['status'],output)
