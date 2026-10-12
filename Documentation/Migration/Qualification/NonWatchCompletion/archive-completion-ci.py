from pathlib import Path
import subprocess,json,gzip,hashlib,re
out=Path('work/completion-evidence/ci');out.mkdir(exist_ok=True)
raw=subprocess.check_output(['gh','api','repos/raster-labs/SwiftJLI/actions/runs/38241825202/jobs','--paginate']);data=json.loads(raw);(out/'jobs.json').write_bytes(raw)
summary=[]
for job in data['jobs']:
 rec={k:job.get(k)for k in ['id','name','status','conclusion','started_at','completed_at','html_url']}
 if job['status']=='completed':
  f=out/(str(job['id'])+'.log.gz')
  if not f.exists():
   log=subprocess.check_output(['gh','api',f"repos/raster-labs/SwiftJLI/actions/jobs/{job['id']}/logs"])
   with f.open('wb') as stream:
    with gzip.GzipFile(fileobj=stream,mode='wb',mtime=0)as z:z.write(log)
  log=gzip.decompress(f.read_bytes());text=log.decode('utf-8','replace')
  rec['logSHA256']=hashlib.sha256(log).hexdigest()
  rec['testResultLines']=[l for l in text.splitlines()if re.search(r'Test run with .* tests|checks passed|tests passed|Executed .* tests|simulator passed|identity records',l)]
 summary.append(rec)
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print([(x['name'],x['conclusion'])for x in summary])
