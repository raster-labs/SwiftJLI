from pathlib import Path
import subprocess,json,hashlib,collections,datetime
w=Path('/private/tmp/swiftjli-round5-flat-small-recovery');e=Path('/private/tmp/swiftjli-round5-evidence/flat-small-recovery-guards');oldE=e.parent/'flat-small-recovery';sha=lambda b:hashlib.sha256(b).hexdigest();git=lambda *a:subprocess.check_output(['git','-C',str(w),*a])
initial=json.loads((oldE/'source.json').read_text());current=json.loads((e/'source.json').read_text());rev=git('rev-parse','HEAD').decode().strip();assert rev=='bbc9ebe1a1e6c5fbe3839c697e562980d2a4a737';assert git('status','--porcelain')==b''
paths=git('ls-tree','-r','--name-only','HEAD','--','Package.swift','Sources','Tests').decode().splitlines();assert len(paths)==186
queries=[]
for receipt in [initial,current]:
 assert sorted(x['path'] for x in receipt['files'])==paths
 for f in receipt['files']:queries.extend([receipt['sourceRevision']+':'+f['path'],f['equalsParent']+':'+f['path']])
queries=list(dict.fromkeys(queries));data=subprocess.check_output(['git','-C',str(w),'cat-file','--batch'],input=('\n'.join(queries)+'\n').encode());pos=0;blobs={}
for query in queries:
 end=data.index(b'\n',pos);head=data[pos:end].split();assert head[1]==b'blob';n=int(head[2]);blobs[query]=data[end+1:end+1+n];pos=end+2+n
assert pos==len(data)
proof=[]
for receipt in [initial,current]:
 for f in receipt['files']:
  b=blobs[receipt['sourceRevision']+':'+f['path']];p=blobs[f['equalsParent']+':'+f['path']]
  assert b==p and sha(b)==f['sha256']
  if receipt is current:assert (w/f['path']).read_bytes()==b
counts=collections.Counter(f['equalsParent'] for f in initial['files'])
changes=git('diff','--name-only',initial['sourceRevision'],rev,'--').decode().splitlines();assert changes==['Tests/SwiftJLITests/Native/DCZeroPairTests.swift']
p='Sources/SwiftJLI/Native/Decoder/JLIDecoder.swift';s=(w/p).read_text();start=s.index('    private static func losslessSmallGrayInto(');stop=s.index('    /// The small-scan caller',start);small=s[start:stop];d=small.index('        if predictor == 1 {');h=small.index('        let history = UnsafeMutableBufferPointer<Int32>.allocate');assert d<h
helper=s[s.index('    private static func losslessSmallLeftInto('):s.index('    @inline(__always)\n    private static func losslessDifference',s.index('    private static func losslessSmallLeftInto('))]
assert 'allocate(' not in helper and 'deallocate(' not in helper and 'var firstSample = half' in helper
r={'reviewedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'candidateRevision':rev,'clean':True,'contract':'0.10.0','firstCompositionRevision':initial['sourceRevision'],'trackedPackageSourceTestCount':186,'allDeclaredParentBlobsByteEqual':True,'allCurrentFilesEqualPinnedGitBlobs':True,'firstCompositionParentFileCounts':dict(counts),'guardCommitChangedOnly':changes,'sourceReceiptSHA256':sha((e/'source.json').read_bytes()),'priorSourceReceiptSHA256':sha((oldE/'source.json').read_bytes()),'smallLeftSource':{'predictor1DispatchBeforeHistoryAllocation':True,'localFirstSampleOnlyNoAllocateDeallocate':True,'parentExact':initial['parents']['tinyLeft'],'scope':'Validated small borrowed greyscale predictor1 path; same difference/modulo/restart/write/check sequence; source-only review. Emitted-code proof deferred until benchmark CPU handoff.'},'productionMechanicallyUnchangedByGuardCommit':True,'acceptance':'Source proof only. Does not replace benchmark, sanitizer or broader qualification gates.'}
out=e/'independent-source-review.json';assert not out.exists();out.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
