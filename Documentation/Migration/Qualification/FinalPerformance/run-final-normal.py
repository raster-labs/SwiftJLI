from pathlib import Path
import json,time,subprocess
root=Path.cwd();out=root/'work/evidence/final-performance';marker=out/'rgb-encode-attribution-sources.json'
while not marker.exists():time.sleep(5)
assert json.loads(marker.read_text())['status']=='passed'
binary=root/'work/build-benchmark-fused-u12/arm64-apple-macosx/release/Benchmark';results=[]
for i in [1,2]:
 with (out/f'public-normal-{i}.jsonl').open('w') as stdout,(out/f'public-normal-{i}.stderr').open('w') as stderr:r=subprocess.run(['/usr/bin/caffeinate','-i',str(binary)],stdout=stdout,stderr=stderr,timeout=180)
 results.append({'run':i,'exitCode':r.returncode});assert r.returncode==0
(out/'normal-results.json').write_text(json.dumps({'status':'passed','commands':results},indent=2)+'\n');print('Final normal comparisons passed',flush=True)
