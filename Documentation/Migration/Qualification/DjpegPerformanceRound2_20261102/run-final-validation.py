import datetime, hashlib, json, os, subprocess, sys
from pathlib import Path
repo=Path("/private/tmp/swiftjli-djpeg-round2")
out=Path("/private/tmp/swiftjli-round2-evidence")
env=os.environ.copy(); env["DEVELOPER_DIR"]="/Applications/Xcode.app/Contents/Developer"
checks=[
("baseline-tests", ["swift", "test", "--package-path", "/private/tmp/swiftjli-djpeg-performance", "-c", "release", "--jobs", "4", "--scratch-path", "/private/tmp/swiftjli-round2-final-baseline-build"]),
("release-tests", ["swift", "test", "-c", "release", "--jobs", "4", "--scratch-path", "/private/tmp/swiftjli-round2-final-build"]),
("release-cli", ["python3", "Scripts/test-cli.py", "--binary", "/private/tmp/swiftjli-round2-final-build/out/Products/Release/swiftjli-cli", "--output", "/private/tmp/swiftjli-round2-qualification-cli"]),
("asan-tests", ["swift", "test", "--jobs", "4", "--scratch-path", "/private/tmp/swiftjli-round2-final-asan", "--sanitize", "address"]),
("asan-cli", ["python3", "Scripts/test-cli.py", "--binary", "/private/tmp/swiftjli-round2-final-asan/out/Products/Debug/swiftjli-cli", "--output", "/private/tmp/swiftjli-round2-qualification-asan-cli"]),
("tsan-tests", ["swift", "test", "--jobs", "4", "--scratch-path", "/private/tmp/swiftjli-round2-final-tsan", "--sanitize", "thread", "--filter", "LosslessLookaheadTests|LosslessRowStorageTests|LosslessDifferenceTests|ScopedACDecoderTests|ACLookaheadTests|NativeExecutionTests|CLISynchronousExecutionTests|OwnershipTests|CancellationPublicationTests"]),
("lossless-interop", ["python3", "Scripts/verify-lossless-interop.py", "--output-dir", "/private/tmp/swiftjli-round2-final-lossless-oracle", "--scratch-path", "/private/tmp/swiftjli-round2-final-oracle-build"]),
("dct-interop", ["python3", "Scripts/verify-dct-interop.py", "--output-dir", "/private/tmp/swiftjli-round2-final-dct-oracle", "--scratch-path", "/private/tmp/swiftjli-round2-final-oracle-build"])
]
def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
result={"startedUTC":now(),"cwd":str(repo),"environmentOverrides":{"DEVELOPER_DIR":env["DEVELOPER_DIR"]},"checks":[]}
if "--resume" in sys.argv:
 result=json.loads((out/"validation.json").read_text())
 result["checks"]=[r for r in result["checks"] if r["exitCode"]==0]
completed={r["name"] for r in result["checks"]}
for name,command in checks:
 if name in completed: continue
 record={"name":name,"command":command,"startedUTC":now(),"log":name+".log"}
 print("Starting",name,flush=True)
 with (out/record["log"]).open("w") as log:
  record["exitCode"]=subprocess.run(command,cwd=repo,env=env,stdout=log,stderr=subprocess.STDOUT).returncode
 record["finishedUTC"]=now(); result["checks"].append(record)
 (out/"validation.json").write_text(json.dumps(result,indent=2)+"\n")
 print("Finished",name,"exit",record["exitCode"],flush=True)
 if record["exitCode"]: raise SystemExit(record["exitCode"])
result["finishedUTC"]=now(); (out/"validation.json").write_text(json.dumps(result,indent=2)+"\n")
