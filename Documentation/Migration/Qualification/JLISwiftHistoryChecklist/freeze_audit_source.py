from pathlib import Path
import hashlib,json,shutil,subprocess
repo=Path('/Users/pushparaj/Documents/Codex/2026-10-13/check-which-milestones-are-completed-and/work/SwiftJLI')
root=Path(__file__).resolve().parent;dst=root/'audit-source'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
paths=sorted([p for part in ['Sources','Tests'] for p in (repo/part).rglob('*') if p.is_file()]+[repo/'Package.swift',repo/'AGENTS.md'])
before={str(p.relative_to(repo)):digest(p) for p in paths}
assert not dst.exists()
for p in paths:
 q=dst/p.relative_to(repo);q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
assert before=={str(p.relative_to(repo)):digest(p) for p in paths}
assert before=={rel:digest(dst/rel) for rel in before}
(root/'audit-source-manifest.json').write_text(json.dumps({'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'files':before},indent=2)+'\n')
(root/'audit-start-diff.patch').write_bytes(subprocess.check_output(['git','diff','44e3807','--','Sources','Tests','Package.swift'],cwd=repo))
print('Frozen',len(before),'source/test/package/instruction files')
