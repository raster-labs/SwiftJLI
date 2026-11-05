import datetime,hashlib,json,os,subprocess
from pathlib import Path
root=Path("/private/tmp/swiftjli-djpeg-round2"); out=Path("/private/tmp/swiftjli-round2-evidence")
env=os.environ.copy(); env["DEVELOPER_DIR"]="/Applications/Xcode.app/Contents/Developer"
baseline="/private/tmp/swiftjli-round2-final-baseline-build/out/Products/Release"
candidate="/private/tmp/swiftjli-round2-final-build/out/Products/Release"
common=["python3","Scripts/benchmark-djpeg.py","--baseline",baseline+"/swiftjli-cli","--candidate",candidate+"/swiftjli-cli","--djpeg","/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/djpeg"]
commands=[
("cli-original",common+["--fixtures","/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory","--output",str(out/"cli-original.json")]),
("cli-patterns",common+["--matrix","lossless-patterns","--fixtures","/private/tmp/swiftjli-native-matrix-fixtures","--output",str(out/"cli-patterns.json")]),
("native-lossless",["python3",str(out/"run-native-lossless.py")]),
("native-dct",["python3","/private/tmp/swiftjli-round2-final-dct-benchmark.py","--baseline-products",baseline,"--candidate-products",candidate,"--output",str(out/"native-dct.json")])]
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def check_pin():
 p=json.loads((out/"initial-toolchain.json").read_text())
 for key in ["swiftc","swift-frontend","djpeg"]:
  assert hashlib.sha256(Path(p[key]["path"]).read_bytes()).hexdigest()==p[key]["sha256"],key+" changed"
 s=json.loads((out/"source-manifest.json").read_text())
 for f,h in s["sha256"].items():assert hashlib.sha256((root/f).read_bytes()).hexdigest()==h,f+" changed"
check_pin(); record={"startedUTC":now(),"commands":[]}
for name,cmd in commands:
 print("Starting",name,flush=True); r={"name":name,"command":cmd,"startedUTC":now()}
 with (out/(name+".log")).open("w") as log:r["exitCode"]=subprocess.run(cmd,cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT).returncode
 r["finishedUTC"]=now();record["commands"].append(r);(out/"benchmark-commands.json").write_text(json.dumps(record,indent=2)+"\n")
 print("Finished",name,"exit",r["exitCode"],flush=True)
 if r["exitCode"]:raise SystemExit(r["exitCode"])
 check_pin()
record["finishedUTC"]=now();(out/"benchmark-commands.json").write_text(json.dumps(record,indent=2)+"\n")
