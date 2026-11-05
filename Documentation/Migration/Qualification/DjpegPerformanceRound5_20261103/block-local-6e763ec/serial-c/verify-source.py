from pathlib import Path
import subprocess, hashlib, json, difflib, datetime
w=Path('/private/tmp/swiftjli-round5-group4-fma-serial-c')
e=Path('/private/tmp/swiftjli-round5-evidence/group4-fma-serial-c')
parent='db1f5c7a31df33a8c6cf2264ab8f894aae302052'; old='a81f8331b6dabcd5ebe584f9b6ef7a93a3ea2043'
def git(*args): return subprocess.check_output(['git','-C',str(w),*args])
def sha(b): return hashlib.sha256(b).hexdigest()
def blob(rev,p): return git('show',rev+':'+p)
helper='Sources/SwiftJLI/Native/Entropy/CSequentialGreyscaleDecoder.swift'
fallback='Sources/SwiftJLI/Native/Entropy/SequentialGreyscaleDecoder.swift'
test='Tests/SwiftJLITests/Native/CSequentialGreyscaleTests.swift'
public='Tests/SwiftJLITests/Native/CACPublicPipelineTests.swift'
oldhelper=blob(old,helper).decode(); newhelper=(w/helper).read_text()
expected=oldhelper.replace('        windowBlocks: Int = SequentialGreyscalePlan.maximumBatchBlocks,\n','        windowBlocks: Int = SequentialGreyscalePlan.maximumBatchBlocks,\n        transformGroupBlocks: Int = SequentialGreyscalePlan.maximumBatchBlocks,\n').replace('                  restartInterval >= 0, windowBlocks > 0,\n','                  restartInterval >= 0,\n                  transformGroupBlocks == 1024 || transformGroupBlocks == 256,\n                  windowBlocks > 0,\n').replace('windowBlocks % 1024','windowBlocks % transformGroupBlocks').replace('let canonicalEnd = index + 1024 - index % 1024','let groupEnd = index + transformGroupBlocks - index % transformGroupBlocks').replace('blocksPerRow, canonicalEnd','blocksPerRow, groupEnd')
assert expected==newhelper
f=(w/fallback).read_text(); s=f.index('        if try CSequentialGreyscaleDecoder.decodeBatchesIfEligible('); t=f.index('        let capacity',s); dispatch=f[s:t]
assert len(dispatch.splitlines())==6
assert (f[:s]+f[t:]).encode()==blob(parent,fallback)
tracked=git('ls-tree','-r','--name-only',parent,'--','Package.swift','Sources','Tests').decode().splitlines()
files=[]; modified=[]
for p in tracked:
    before=blob(parent,p); after=(w/p).read_bytes(); changed=before!=after
    files.append({'path':p,'parentSHA256':sha(before),'candidateSHA256':sha(after),'equalParent':not changed})
    if changed: modified.append(p)
assert sorted(modified)==sorted([fallback,public])
for p in [helper,test]:
    assert p not in tracked
    files.append({'path':p,'candidateSHA256':sha((w/p).read_bytes()),'newFile':True})
patch=git('diff','--binary',parent,'--',fallback,public).decode()
for p in [helper,test]: patch+=''.join(difflib.unified_diff([], (w/p).read_text().splitlines(keepends=True),fromfile='/dev/null',tofile='b/'+p))
(e/'source.patch').write_text(patch)
(e/'helper-adaptation.patch').write_text(''.join(difflib.unified_diff(oldhelper.splitlines(keepends=True),newhelper.splitlines(keepends=True),fromfile='a81/'+helper,tofile='candidate/'+helper)))
olddecision=Path('/private/tmp/swiftjli-round5-evidence/c-row-serial-isolated/decision.json')
receipt={'status':'source-preparation-only-unbuilt','createdUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'worktree':str(w),'branch':'codex/round5-group4-fma-serial-c','parentRevision':parent,'historicalHelperRevision':old,'contract':'0.10.0','expectedToolchain':'Swift 6.4.2; manifest minimum Swift 6.2','proof':{'parentTrackedPackageSourceTestFiles':len(tracked),'unchangedParentFiles':len(tracked)-len(modified),'modifiedExistingFiles':modified,'newFiles':[helper,test],'sixLineDispatch':True,'fallbackExactParentAfterRemovingDispatch':True,'helperExactHistoricalAfterOnlyGroupAdaptation':True,'noCReaderTransformParserAdmissionOrPackageChanges':True},'files':files,'patchSHA256':sha(patch.encode()),'testSourceSHA256':sha((w/test).read_bytes()),'sourceReview':{'authorReview':'No actionable source defect found; no execution performed.','independentReviewer':'/root/round2_startup','independentFindings':'Group guard precedes modulo; checked capacity and index bounds; DC/restart state spans windows; failed entropy never publishes; handled is only set after success; scoped metadata/input/coefficient borrows enclose synchronous consumer; workers join and restore binding; unsupported precision/backend/metadata declines side-effect-free.','testsPrepared':['Six test declarations covering eligible 8/12 C admission, 9-bit/scalar/nil/oversized metadata decline, exact coefficient oracle and reuse','256 groups with restart255/256/257; 1024/2048 windows and restart1023/1024','Partial final15-block window; 13 invalid extent/group cases with retained entropy state','Truncated batch publication and throwing Float rebind restoration at256/1024','Existing public integer/Float pipeline exactness and padding tests retained; only route-description comment updated']},'history':{'a81DecisionPath':str(olddecision),'a81DecisionSHA256':sha(olddecision.read_bytes()),'a81HeldReason':'ProgressiveRGB8-512 worker8 repeatedly regressed +5.7361%/+9.8920%; single-worker DCT12 gains were provisional and did not qualify acceptance.','parentDb1HeldReason':'Repeated lossless flat19 +22.4385%/+15.7493%; DCT flat12-512 +5.0769%/+6.3166%. Original failures remain.','newCandidateInheritsNoRuntimeQualification':True},'commandsExecuted':['git diff --check (exit0)','Source-only git blob comparison, SHA256 and patch generation (exit0)'],'unexecuted':['Compilation and affected Release tests','Fresh paired DCT and lossless controls against selected baseline and parent','Sanitisers, CLI, independent JPEG oracle, RSS and other-platform/toolchain qualification'],'acceptance':'Prepared only. No performance claim, no djpeg win and no gate waiver.'}
(e/'source-preparation.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'evidence':str(e),'tracked':len(tracked),'unchanged':len(tracked)-len(modified),'new':2,'helperProof':True,'fallbackProof':True,'patchSHA256':receipt['patchSHA256'],'testSHA256':receipt['testSourceSHA256']}))
