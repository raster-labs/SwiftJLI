"""Independent normal JPEG conformance check using libjpeg-turbo and public CLI."""
from pathlib import Path
import hashlib,json,subprocess,sys
root=Path(__file__).resolve().parent
binary=Path(sys.argv[1]).resolve();fixtures=root/'audit-source/Tests/SwiftJLITests/Fixtures/UpstreamJPEG'
out=root/'valid-jpeg-oracle';out.mkdir(exist_ok=False)
report={'commands':[],'cases':[],'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()}
def run(name,argv):
 r=subprocess.run([str(x) for x in argv],capture_output=True,timeout=60)
 (out/(name+'.stdout')).write_bytes(r.stdout);(out/(name+'.stderr')).write_bytes(r.stderr)
 report['commands'].append({'name':name,'argv':[str(x) for x in argv],'exit_code':r.returncode})
 assert r.returncode==0,(name,r.returncode,r.stderr.decode(errors='replace'))
def tables(data):
 assert data[:2]==b'\xff\xd8';p=2;result=b''
 while data[p+1]!=0xda:
  assert data[p]==255
  n=int.from_bytes(data[p+2:p+4],'big');assert n>=2 and p+2+n<=len(data)
  if data[p+1]==0xc4:result+=data[p:p+2+n]
  p+=2+n
 assert result
 return result
def pnm(data):
 # All files are produced by these known PNM writers; parse three header lines.
 magic,dim,maximum,pixels=data.split(b'\n',3)
 w,h=map(int,dim.split());m=int(maximum);n=1 if magic==b'P5' else 3
 assert magic in (b'P5',b'P6') and len(pixels)==w*h*n*(1 if m<256 else 2)
 samples=list(pixels) if m<256 else [int.from_bytes(pixels[i:i+2],'big') for i in range(0,len(pixels),2)]
 return (magic,w,h,m),samples
try:
 run('oracle-version',['/opt/homebrew/bin/djpeg','-version'])
 donor=out/'table-donor.jpg'
 run('table-donor',['/opt/homebrew/bin/cjpeg','-quality','17','-optimize','-sample','1x1','-outfile',donor,fixtures/'testorig-444-oracle.pnm'])
 dht=tables(donor.read_bytes())
 for stem in ['testorig-444','testorig-444-progressive','testimgint-444','testimgint-444-progressive','monkey12-444','monkey12-444-progressive']:
  data=(fixtures/(stem+'.jpg')).read_bytes();assert data[-2:]==b'\xff\xd9'
  original=out/(stem+'-original.jpg');original.write_bytes(data)
  later=out/(stem+'-later-tables.jpg');later.write_bytes(data[:-2]+dht+b'\xff\xd9')
  ref=[];ours={}
  for label,src in [('original',original),('later',later)]:
   dst=out/(stem+'-'+label+'-oracle.ppm')
   run(stem+'-'+label+'-oracle',['/opt/homebrew/bin/djpeg','-strict','-dct','int','-pnm','-outfile',dst,src]);ref.append(pnm(dst.read_bytes()))
   for backend in ['scalar','automatic']:
    dst=out/(stem+'-'+label+'-'+backend+'.ppm')
    run(stem+'-'+label+'-'+backend,[binary,'decode','-i',src,'-o',dst,'--backend',backend]);ours[label,backend]=pnm(dst.read_bytes())
  assert ref[0]==ref[1],stem+' oracle changed'
  differences={}
  for backend in ['scalar','automatic']:
   assert ours['original',backend]==ours['later',backend],stem+' '+backend+' changed'
   desc,samples=ours['later',backend];assert desc==ref[1][0]
   maxerr=max(abs(a-b) for a,b in zip(samples,ref[1][1]));assert maxerr<=(2 if desc[3]==255 else 4),(stem,backend,maxerr)
   differences[backend]=maxerr
  report['cases'].append({'name':stem,'original_sha256':hashlib.sha256(data).hexdigest(),'with_later_tables_sha256':hashlib.sha256(later.read_bytes()).hexdigest(),'all_sample_comparisons_passed':True,'oracle_maximum_difference':differences})
 report['status']='passed'
finally:
 report['files_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file()}
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'status':report['status'],'cases':len(report['cases']),'commands':len(report['commands'])}))
