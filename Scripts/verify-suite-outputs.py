#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independently verify all four-codec integration outputs; development tools only."""
import argparse, hashlib, importlib.util, json, re, shutil, subprocess
from pathlib import Path
spec = importlib.util.spec_from_file_location('pgm', Path(__file__).with_name('verify-cross-codec-outputs.py'))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--input', type=Path, required=True); p.add_argument('--output', type=Path, required=True)
p.add_argument('--oracle-image', required=True, help='Docker image with g++, libcharls-dev and libjxl-tools')
a = p.parse_args(); source=a.input.resolve(); out=a.output.resolve(); out.mkdir(parents=True, exist_ok=False)
root=Path(__file__).resolve().parents[1]; cpp=root/'Examples/SuitePairIntegration/Oracle/charls-pgm.cpp'
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
record={'status':'running','commands':[], 'cases':[], 'charlsSourceSHA256':sha(cpp),
        'oracleImage':subprocess.check_output(['docker','image','inspect',a.oracle_image,'--format','{{.Id}}'],text=True).strip()}
def save(): (out/'results.json').write_text(json.dumps(record,indent=2)+'\n')
def run(command):
    r=subprocess.run(command,capture_output=True,text=True,timeout=120)
    record['commands'].append(dict(argv=command,exitCode=r.returncode,stdout=r.stdout,stderr=r.stderr)); save()
    if r.returncode: raise RuntimeError(record['commands'][-1])
container=['docker','run','--rm','--network','none','-v',f'{source}:/inputs:ro','-v',f'{out}:/output','-v',f'{cpp}:/charls-pgm.cpp:ro',a.oracle_image]
try:
    run(container+['sh','-c','g++ -O2 /charls-pgm.cpp -lcharls -o /output/charls-pgm && dpkg-query -W libcharls-dev libjxl-tools && djxl --version'])
    run([shutil.which('djpeg'),'-version'])
    files=sorted(source.glob('*.*')); assert len(files)==72
    for f in files:
        match=re.fullmatch(r'(\d+)x(\d+)-u(12|16)-(jli|j2k|jls|jxl)-to-(jli|j2k|jls|jxl)\.(jpg|j2k|jls|jxl)',f.name)
        assert match and match[4]!=match[5]
        w,h,bits=map(int,match.groups()[:3]); maximum=(1<<bits)-1; decoded=out/(f.name+'.pgm')
        if f.suffix=='.jpg': command=[shutil.which('djpeg'),'-pnm','-outfile',str(decoded),str(f)]
        elif f.suffix=='.j2k': command=[shutil.which('opj_decompress'),'-i',str(f),'-o',str(decoded)]
        elif f.suffix=='.jls': command=container+['/output/charls-pgm','/inputs/'+f.name,'/output/'+decoded.name]
        else: command=container+['djxl','/inputs/'+f.name,'/output/'+decoded.name,'--num_threads=1']
        run(command)
        width,height,m,samples=module.pgm(decoded)
        assert (width,height,m)==(w,h,maximum), f'Independent precision mismatch: {f.name}: {width,height,m}'
        expected=[0 if x==0 and y==0 else maximum if x==1 and y==0 else (x*193+y*357+x*y*17)&maximum for y in range(h) for x in range(w)]
        # libjxl 0.7 djxl writes full-range UInt16 PNM samples even when the
        # PNM maximum records the original 12-bit precision. Its float scaling
        # can round by one 16-bit unit; require exact original integer recovery.
        scaling_error = 0
        if f.suffix == '.jxl' and bits < 16:
            scaled = [(v * 65535 + maximum // 2) // maximum for v in expected]
            scaling_error = max(abs(a-b) for a,b in zip(samples, scaled))
            assert scaling_error <= 1, f'Independent scaled samples differ: {f.name}'
            samples = [(v * maximum + 32767) // 65535 for v in samples]
        assert samples==expected, f'Independent samples differ: {f.name}'
        record['cases'].append(dict(file=f.name,inputSHA256=sha(f),outputSHA256=sha(decoded),samples=len(samples),exact=True,normalised16BitRoundingError=scaling_error)); save()
    record['status']='passed'; print('PASS: 72 independent four-codec decodes, exact precision and samples')
except BaseException as error: record.update(status='failed',error=repr(error)); raise
finally: save()
