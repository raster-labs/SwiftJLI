from pathlib import Path
import subprocess,urllib.request,hashlib,json,concurrent.futures
root=Path('work/SwiftJLI');out=Path('work/completion-evidence/contracts');out.mkdir(exist_ok=True)
names=[line.split()[1] for line in (root/'Documentation/COMMON_CONTRACT_SHA256.txt').read_text().splitlines()]
records=[]
for repo in ['SwiftJLI','SwiftJ2K','SwiftJLS','SwiftJXL']:
 revision=subprocess.check_output(['gh','api',f'repos/raster-labs/{repo}/commits/main','--jq','.sha'],text=True).strip()
 def check(name):
  url=f'https://raw.githubusercontent.com/raster-labs/{repo}/{revision}/Documentation/{name}'
  with urllib.request.urlopen(url,timeout=30) as r:data=r.read()
  actual=hashlib.sha256(data).hexdigest();expected=hashlib.sha256((root/'Documentation'/name).read_bytes()).hexdigest()
  return {'document':name,'sha256':actual,'matchesCandidate':actual==expected,'url':url}
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:documents=list(pool.map(check,names))
 records.append({'repository':repo,'revision':revision,'documents':documents})
 print(repo,revision[:7],sum(d['matchesCandidate'] for d in documents),'/ 7',flush=True)
(out/'results.json').write_text(json.dumps({'repositories':records,'allMatch':all(d['matchesCandidate'] for r in records for d in r['documents'])},indent=2)+'\n')
if not all(d['matchesCandidate'] for r in records for d in r['documents']):raise SystemExit(1)
