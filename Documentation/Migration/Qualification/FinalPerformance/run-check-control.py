import pathlib,json,subprocess,hashlib
r=pathlib.Path.cwd();out=r/'work/evidence/final-performance';binary=r/'work/build-public-check-control/arm64-apple-macosx/release/Benchmark';control=r/'work/SwiftJLI-check-final';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
record={'diagnosticOnly':'Required cancellation and deadline checks removed in isolated copy; never qualifies the shipping library','binarySHA256':sha(binary),'sourceHashes':{str(p.relative_to(control)):sha(p) for p in sorted((control/'Sources').rglob('*.swift'))},'commands':[]}
for i in [1,2]:
 with (out/f'check-control-{i}.jsonl').open('w') as stdout,(out/f'check-control-{i}.stderr').open('w') as stderr:result=subprocess.run([str(binary)],stdout=stdout,stderr=stderr,timeout=180)
 record['commands'].append({'iteration':i,'exitCode':result.returncode});assert result.returncode==0
record['status']='passed';(out/'check-control-results.json').write_text(json.dumps(record,indent=2)+'\n')
print('Diagnostic check-cost control completed',flush=True)
