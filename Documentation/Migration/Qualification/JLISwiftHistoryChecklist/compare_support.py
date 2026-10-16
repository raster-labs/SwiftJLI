from pathlib import Path
import hashlib,json,re,subprocess
source=Path('/Users/pushparaj/Documents/Codex/2026-10-15/i-x20/work/JLISwift-20261014')
target=Path('/Users/pushparaj/Documents/Codex/2026-10-13/check-which-milestones-are-completed-and/work/SwiftJLI')
out=Path('/Users/pushparaj/Documents/Codex/2026-10-15/i-x20/work/history-checklist')
def sha(b): return hashlib.sha256(b).hexdigest()
def normalise(s):
 s=re.sub(r'\bpublic ', '',s)
 s=s.replace('#if canImport(Accelerate)\n','').replace('\n#endif','')
 return s.strip()
rows=[]
for name in ['DICOMReader.swift','DICOMWriter.swift','DICOMWindowRenderer.swift']:
 a=source/'Sources/JLIDICOM'/name;b=target/'Tests/SwiftJLITests/Support'/name
 rows.append(dict(source=str(a.relative_to(source)),target=str(b.relative_to(target)),sourceSHA256=sha(a.read_bytes()),targetSHA256=sha(b.read_bytes()),normalisedIdentical=normalise(a.read_text())==normalise(b.read_text())))
tests=[]
for name in ['DICOMReaderTests.swift','DICOMWriterTests.swift','DICOMColorTests.swift','LosslessTests.swift','LosslessRestartTests.swift','MetadataTests.swift','MedicalSafetyTests.swift','ConformanceEvidenceTests.swift','RegressionCorpusTests.swift']:
 a=source/'Tests/JLISwiftTests'/name;b=target/'Tests/SwiftJLITests/Native'/name
 tests.append(dict(source=str(a.relative_to(source)),target=str(b.relative_to(target)),sourceSHA256=sha(a.read_bytes()),targetSHA256=sha(b.read_bytes()),sourceTestDeclarations=len(re.findall(r'@Test\b',a.read_text())),targetTestDeclarations=len(re.findall(r'@Test\b',b.read_text()))))
r={'predecessor':subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip(),'target':subprocess.check_output(['git','rev-parse','HEAD'],cwd=target,text=True).strip(),'normalisation':'Remove public access modifiers and canImport(Accelerate) wrapper only; no algorithm changes normalised away.','support':rows,'tests':tests,'interpretation':'These DICOM algorithms are retained in test support, not a shipping library product. Test counts measure declarations, not executed results.'}
(out/'codex-inherited-support-comparison.json').write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps(r,indent=2))
