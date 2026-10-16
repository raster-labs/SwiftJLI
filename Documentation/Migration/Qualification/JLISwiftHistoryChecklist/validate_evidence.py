from pathlib import Path
import hashlib,json,re,subprocess
repo=Path('/Users/pushparaj/Documents/Codex/2026-10-13/check-which-milestones-are-completed-and/work/SwiftJLI')
pre=Path('/Users/pushparaj/Documents/Codex/2026-10-15/i-x20/work/JLISwift-20261014')
root=Path(__file__).resolve().parent
matrix=repo/'Documentation/Migration/Qualification/JLISwiftHistoryChecklist/history-checklist-matrix.json'
r=json.loads(matrix.read_text());rows=r['checklist'];errors=[];file_refs=[]
assert len(rows)==17 and len({i['category_id'] for i in rows})==10
for pin in r['earlier_jliswift_pins']+[r['predecessor_jliswift_commit']]:
 p=subprocess.run(['git','rev-parse','--verify',pin+'^{commit}'],cwd=pre,capture_output=True,text=True)
 if p.returncode or p.stdout.strip()!=pin:errors.append('invalid predecessor pin: '+pin)
for row in rows:
 for value in row.get('swiftjli_files',[]):
  p=repo/value.split(' (')[0].split('#')[0]
  if not p.is_file(): errors.append(row['item_id']+' missing path: '+value)
 for name in row.get('verification_tests',[]):
  if 'dicom-normal-value-oracle.swift' in name:continue
  label=name.split(' (')[0]
  match=re.search(r'\((Tests/[^)#]+)(?:#L(\d+))?\)',name)
  if match:
   p=repo/match[1]
   if not p.is_file():errors.append(row['item_id']+' missing test file: '+name);continue
   text=p.read_text();leaf=label.split('.')[-1]
   if label==p.stem:file_refs.append(label);continue
   if not re.search(r'\bfunc\s+'+re.escape(leaf)+r'\s*\(',text):errors.append(row['item_id']+' missing test method: '+name)
   if match[2] and leaf not in text.splitlines()[int(match[2])-1]:errors.append(row['item_id']+' wrong test anchor: '+name)
  else:errors.append(row['item_id']+' test reference lacks file path: '+name)
for name,record in r.get('files_recorded',{}).items():
 if hashlib.sha256((repo/name).read_bytes()).hexdigest()!=record['sha256']:errors.append('source hash mismatch: '+name)
manifest=json.loads((root/'audit-source-manifest.json').read_text())['files']
for name,h in manifest.items():
 if hashlib.sha256((repo/name).read_bytes()).hexdigest()!=h:errors.append('tested snapshot changed: '+name)
result={'rows':len(rows),'categories':len({i['category_id'] for i in rows}),'verified_source_snapshot_files':len(manifest),'file_level_test_references':sorted(set(file_refs)),'errors':errors,'status':'passed' if not errors else 'failed'}
(root/'codex-evidence-validation.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
raise SystemExit(bool(errors))
