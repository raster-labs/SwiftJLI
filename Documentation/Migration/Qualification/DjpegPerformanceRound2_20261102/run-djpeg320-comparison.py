import datetime,hashlib,json,subprocess
from pathlib import Path
root=Path("/private/tmp/swiftjli-djpeg-round2");out=Path("/private/tmp/swiftjli-round2-evidence")
pin=json.loads((out/"djpeg320-pin.json").read_text())
assert hashlib.sha256(Path(pin["path"]).read_bytes()).hexdigest()==pin["sha256"]
common=["python3","Scripts/benchmark-djpeg.py","--baseline","/private/tmp/swiftjli-round2-final-baseline-build/out/Products/Release/swiftjli-cli","--candidate","/private/tmp/swiftjli-round2-final-build/out/Products/Release/swiftjli-cli","--djpeg",pin["path"]]
result={"commands":[]}
for name,matrix,fixtures in [("cli-original-320","original","/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory"),("cli-patterns-320","lossless-patterns","/private/tmp/swiftjli-native-matrix-fixtures")]:
 command=common+["--matrix",matrix,"--fixtures",fixtures,"--output",str(out/(name+".json"))]
 r={"name":name,"command":command,"startedUTC":datetime.datetime.now(datetime.timezone.utc).isoformat()}
 print("Starting",name,flush=True)
 with (out/(name+".log")).open("w") as log:r["exitCode"]=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT).returncode
 r["finishedUTC"]=datetime.datetime.now(datetime.timezone.utc).isoformat();result["commands"].append(r)
 (out/"benchmark-commands-320.json").write_text(json.dumps(result,indent=2)+"\n")
 print("Finished",name,"exit",r["exitCode"],flush=True)
 if r["exitCode"]:raise SystemExit(r["exitCode"])
assert hashlib.sha256(Path(pin["path"]).read_bytes()).hexdigest()==pin["sha256"]
