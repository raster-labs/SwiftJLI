#!/usr/bin/env python3
"""Fresh execution of the retained six-profile large-lossless correctness method."""
import argparse
import datetime
import hashlib
import json
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
sha = lambda path: hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary', type=pathlib.Path, required=True)
p.add_argument('--source-revision', required=True)
p.add_argument('--output', type=pathlib.Path, required=True)
p.add_argument('--execute', action='store_true')
a = p.parse_args()
plan = json.loads((HERE / 'prepared.json').read_text())
assert a.binary.resolve() == pathlib.Path(plan['binary']).resolve()
assert a.source_revision == plan['sourceRevision']
if not a.execute:
    print(json.dumps({'status': 'NOT EXECUTED', 'sourceRevision': a.source_revision,
                      'method': plan['method'], 'output': str(a.output)}, indent=2))
    raise SystemExit(0)

assert plan.get('executionStatus') == 'authorised-by-parent', 'Execution is explicitly held; parent must authorise a fresh recorded plan'
# Every execution uses a fresh directory, including after a failed attempt.
assert not a.output.exists(), 'Refusing to overwrite a retained oracle run'
pins = dict(plan['inputSHA256'])
pins.update(plan['sourceSHA256'])
pins[str(HERE / 'run.py')] = plan['runnerSHA256']
pins[str(HERE / 'prepared.json')] = sha(HERE / 'prepared.json')
assert all(pathlib.Path(path).is_file() and sha(path) == digest for path, digest in pins.items())
assert all(str(pathlib.Path(path).resolve()) == target for path, target in plan['resolvedDylibs'].items())
assert subprocess.check_output(['git', '-C', plan['worktree'], 'rev-parse', 'HEAD'], text=True).strip() == a.source_revision
assert subprocess.check_output(['git', '-C', plan['worktree'], 'status', '--porcelain'], text=True).strip() == ''
a.output.mkdir(parents=True, exist_ok=False)
root = a.output
turbo = pathlib.Path(plan['turboBin'])
r = {'status': 'running', 'startedUTC': now(), 'sourceRevision': a.source_revision,
     'method': plan['method'], 'preparedSHA256': sha(HERE / 'prepared.json'),
     'runnerSHA256': sha(HERE / 'run.py'), 'inputSHA256': pins,
     'binarySHA256': sha(a.binary), 'cjpegSHA256': sha(turbo / 'cjpeg'),
     'djpegSHA256': sha(turbo / 'djpeg'), 'commands': [], 'profiles': [],
     'compilerProvenance': plan['compilerProvenance'],
     'qualificationReceipts': plan['qualificationReceipts'],
     'limitation': 'Correctness only; no timing, RSS or universal performance claim.'}

def save():
    (root / 'receipt.json').write_text(json.dumps(r, indent=2) + '\n')

def run(cmd):
    number = len(r['commands']) + 1
    stdout_path = root / f'command-{number:02d}.stdout.log'
    stderr_path = root / f'command-{number:02d}.stderr.log'
    row = {'command': list(map(str, cmd)), 'startedUTC': now(),
           'stdoutPath': str(stdout_path), 'stderrPath': str(stderr_path)}
    r['commands'].append(row)
    save()
    stdout = stderr = b''
    try:
        result = subprocess.run(cmd, capture_output=True, timeout=120)
        stdout, stderr = result.stdout, result.stderr
        row['exitCode'] = result.returncode
        result.check_returncode()
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or b'', error.stderr or b''
        row.update(failure='timeout', timeoutSeconds=120, exception=repr(error))
        raise
    except BaseException as error:
        row.update(failure=type(error).__name__, exception=repr(error))
        raise
    finally:
        with stdout_path.open('xb') as stream:
            stream.write(stdout)
        with stderr_path.open('xb') as stream:
            stream.write(stderr)
        row.update(finishedUTC=now(), stdoutSHA256=sha(stdout_path), stderrSHA256=sha(stderr_path),
                   stdout=stdout.decode(errors='replace'), stderr=stderr.decode(errors='replace'))
        save()

def pnm(path):
    magic,dimensions,maximum,payload=path.read_bytes().split(b'\n',3)
    w,h=map(int,dimensions.split());maximum=int(maximum);bps=1 if maximum<256 else 2
    assert magic==b'P5' and len(payload)==w*h*bps
    return (magic,w,h,maximum),payload

save()
try:
    for bits,pattern,width,height in [(12,'ramp',2048,17),(16,'ramp',2048,17),(16,'noise',513,257)]:
        for restart in [0,width*2]:
            stem=f'{pattern}-{bits}-{width}x{height}-r{restart}';source=root/(stem+'.pgm')
            maximum=(1<<bits)-1;seed=0x6B291A3F;payload=bytearray()
            for index in range(width*height):
                if pattern=='ramp':value=(index*(1 if bits==12 else 16))&maximum
                else:seed=(seed*1664525+1013904223)&0xffffffff;value=(seed>>8)&maximum
                payload.extend(value.to_bytes(2,'big'))
            source.write_bytes(f'P5\n{width} {height}\n{maximum}\n'.encode()+payload)
            assert sha(source) == plan['qualifiedSourceFixtureSHA256'][stem]
            ours=root/(stem+'-swift.jpg');theirs=root/(stem+'-oracle.jpg')
            run([a.binary,'encode','-i',source,'-o',ours,'--mode','lossless','--predictor','1','--restart-interval',str(restart)])
            run([turbo/'cjpeg','-precision',str(bits),'-lossless','1,0','-optimize','-restart',str(restart)+'B','-outfile',theirs,source])
            checked=[]
            for origin,jpeg in [('swift',ours),('oracle',theirs)]:
                coutput=root/(stem+'-djpeg-'+origin+'.pgm');soutput=root/(stem+'-swift-'+origin+'.pgm')
                run([turbo/'djpeg','-strict','-pnm','-outfile',coutput,jpeg])
                run([a.binary,'decode','-i',jpeg,'-o',soutput,'--output-format','pgm'])
                assert pnm(coutput)==pnm(source),('djpeg',stem,origin)
                assert pnm(soutput)==pnm(source),('swift',stem,origin)
                checked.append({'origin':origin,'jpegSHA256':sha(jpeg),'djpegOutputSHA256':sha(coutput),'swiftOutputSHA256':sha(soutput),'samplesExact':True})
            r['profiles'].append({'stem':stem,'width':width,'height':height,'bits':bits,'restart':restart,'sourceSHA256':sha(source),'outputs':checked});save()
    assert len(r['profiles']) == 6 and len(r['commands']) == 36
    assert sum(len(profile['outputs']) for profile in r['profiles']) == 12
    r['status'] = 'passed'
except BaseException as error:
    r.update(status='failed', failure=repr(error))
    raise
finally:
    r['identityChecks'] = {path: pathlib.Path(path).is_file() and sha(path) == digest
                           for path, digest in pins.items()}
    r['resolvedDylibChecks'] = {path: str(pathlib.Path(path).resolve()) == target for path, target in plan['resolvedDylibs'].items()}
    r['artifactSHA256'] = {str(path): sha(path) for path in sorted(root.iterdir())
                          if path.is_file() and path.name != 'receipt.json'}
    if not all(r['identityChecks'].values()) or not all(r['resolvedDylibChecks'].values()):
        r['status'] = 'failed-artifact-verification'
    r['finishedUTC'] = now()
    save()
if r['status'] != 'passed':
    raise SystemExit(1)
print('Six large lossless profiles passed; twelve streams decoded exactly by both decoders.')
