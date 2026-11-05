#!/usr/bin/env python3
"""Independent synthetic lossless oracles large enough for the C row routes."""
import argparse, datetime, hashlib, json, pathlib, subprocess
p=argparse.ArgumentParser();p.add_argument('--binary',type=pathlib.Path,required=True);p.add_argument('--source-revision',required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=False)
root=a.output;turbo=pathlib.Path('/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
r={'sourceRevision':a.source_revision,'method':'Independent cjpeg/djpeg3.2.1 lossless sample oracles, both encoding directions. Synthetic12/16bit ramp and16bit noise; no point transform, predictor1, row-aligned restarts. CLI public decoding; full samples must equal source. Correctness only, not timing.','binarySHA256':sha(a.binary),'cjpegSHA256':sha(turbo/'cjpeg'),'djpegSHA256':sha(turbo/'djpeg'),'commands':[],'profiles':[],'status':'running'}
def save(): (root/'receipt.json').write_text(json.dumps(r,indent=2)+'\n')
def run(cmd):
    row={'command':list(map(str,cmd)),'startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat()};r['commands'].append(row);save()
    result=subprocess.run(cmd,capture_output=True,timeout=120)
    row.update(exitCode=result.returncode,stdout=result.stdout.decode(errors='replace'),stderr=result.stderr.decode(errors='replace'));save();result.check_returncode()
def pnm(path):
    magic,dimensions,maximum,payload=path.read_bytes().split(b'\n',3)
    w,h=map(int,dimensions.split());maximum=int(maximum);bps=1 if maximum<256 else 2
    assert magic==b'P5' and len(payload)==w*h*bps
    return (magic,w,h,maximum),payload
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
    assert sha(a.binary)==r['binarySHA256']
    r['status']='passed';save();print('Six large lossless profiles passed; twelve streams decoded exactly by both decoders.')
except Exception as error:
    r.update(status='failed',failure=repr(error));save();raise
