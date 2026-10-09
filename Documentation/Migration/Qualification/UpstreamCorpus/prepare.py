import subprocess,json
from pathlib import Path
root=Path('work/external-jpeg-corpus');commands=[]
def run(command):
 r=subprocess.run(command,capture_output=True,text=True);commands.append({'argv':command,'exit_code':r.returncode,'stderr':r.stderr});assert r.returncode==0
for name in ['monkey12','testorig','testimgint']:
 bits=12 if name=='monkey12' else 8
 run(['djpeg','-strict','-dct','int','-pnm','-outfile',str(root/(name+'-input.pnm')),str(root/(name+'.jpg'))])
 for progressive in [False,True]:
  stem=name+'-444'+('-progressive' if progressive else '')
  run(['cjpeg','-precision',str(bits),'-quality','85','-sample','1x1']+(['-progressive'] if progressive else [])+['-outfile',str(root/(stem+'.jpg')),str(root/(name+'-input.pnm'))])
  run(['djpeg','-strict','-dct','int','-pnm','-outfile',str(root/(stem+'-oracle.pnm')),str(root/(stem+'.jpg'))])
(root/'oracle-commands.json').write_text(json.dumps(commands,indent=2)+'\n')
p=Path('work/external-corpus-consumer/Sources/Corpus/main.swift');s=p.read_text();s=s.replace('for name in ["monkey12", "testimgint", "testorig", "testimgari"] {','for name in ["monkey12", "testimgint", "testorig"].flatMap({ [$0, $0 + "-444", $0 + "-444-progressive"] }) + ["testimgari"] {');p.write_text(s)
print('Generated six independently encoded 4:4:4 corpus profiles; fixed max-error gates are 2 (8-bit) and 4 (12-bit) sample units, matching existing DCT qualification')
