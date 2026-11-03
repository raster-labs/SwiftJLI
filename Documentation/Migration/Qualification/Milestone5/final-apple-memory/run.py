#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Refresh ordinary-build Apple retained-frame controls; not a timing benchmark."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--repository", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--revision", required=True, help="Immutable candidate commit whose source must match the checkout")
parser.add_argument("--scratch", type=Path, help="Reuse a known build cache; source and executable are revalidated")
args = parser.parse_args()
if not re.fullmatch(r"[0-9a-f]{40}", args.revision):
    parser.error("--revision must be an explicit immutable 40-character Git commit")
repo = args.repository.resolve()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
if (out / "results.json").exists():
    parser.error("Choose fresh output; an earlier result must not be overwritten")
scratch = args.scratch.resolve() if args.scratch else Path(tempfile.mkdtemp(prefix="swiftjli-m5-apple-memory-", dir="/private/tmp"))
scratch.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer",
           CLANG_MODULE_CACHE_PATH=str(scratch / "clang-cache"),
           SWIFTPM_MODULECACHE_OVERRIDE=str(scratch / "swift-cache"))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def source_hashes():
    paths = [repo / "Package.swift", *sorted((repo / "Sources").rglob("*.swift")),
             *sorted((repo / "Examples/AppleMemoryProbe").rglob("*.swift"))]
    return {str(p.relative_to(repo)): sha(p) for p in paths if ".build" not in p.parts}

report = {"status": "running", "startedUTC": dt.datetime.now(dt.timezone.utc).isoformat(),
          "candidateRevision": args.revision, "reusedBuildCache": args.scratch is not None,
          "sourceHashes": source_hashes(), "commands": [], "scratch": str(scratch),
          "buildEngine": "swiftbuild", "configuration": "release", "sanitizers": False,
          "jobs": 2, "scope": "Apple process allocator retained-frame controls, not performance timings or pure workspace measurements",
          "environmentOverrides": {k: env[k] for k in ("DEVELOPER_DIR", "CLANG_MODULE_CACHE_PATH", "SWIFTPM_MODULECACHE_OVERRIDE")},
          "runnerSHA256": sha(Path(__file__)), "profiles": []}

def save():
    (out / "results.json").write_text(json.dumps(report, indent=2) + "\n")

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def run(label, command, timeout=1200):
    stdout = out / (label + ".stdout")
    stderr = out / (label + ".stderr")
    record = {"label": label, "command": command, "cwd": str(repo),
              "startedUTC": dt.datetime.now(dt.timezone.utc).isoformat(), "stdout": stdout.name, "stderr": stderr.name}
    report["commands"].append(record)
    save()
    print(label, flush=True)
    try:
        with stdout.open("w") as output, stderr.open("w") as errors:
            result = subprocess.run(command, cwd=repo, env=env, stdout=output, stderr=errors, timeout=timeout)
        record["exitCode"] = result.returncode
    except BaseException as error:
        record["error"] = repr(error)
        raise
    finally:
        record["finishedUTC"] = dt.datetime.now(dt.timezone.utc).isoformat()
        record["stdoutSHA256"] = sha(stdout)
        record["stderrSHA256"] = sha(stderr)
        save()
    require(result.returncode == 0, f"{label} exited {result.returncode}")
    return stdout.read_text()

def verify(rows, profile, control):
    modes = {"concurrentEncode", "concurrentDecode", "invalidFinalSample", "encodeAdmissionDenied", "decodeAdmissionDenied", "encodeCancellation", "decodeCancellation"}
    expected = {(size, mode, count) for size in (257, 1024) for mode in modes for count in (2, 32)}
    actual = {(r["width"], r["mode"], r["operations"]) for r in rows}
    require(len(rows) == 28 and actual == expected, "Incomplete or duplicate stress matrix")
    for row in rows:
        require(row["event"] == "stress" and row["profile"] == profile and row["controlCopy"] == control and row["expectedOutcomes"], "Unexpected profile, control or outcome")
        require(row["height"] == row["width"] and row["maximumInFlight"] == 2 and row["workersPerOperation"] == 2, "Unexpected geometry or concurrency")
        require(row["maximumWorkspaceBytes"] == 1024 ** 3 and row["maximumMemoryBytes"] == 2 * 1024 ** 3, "Unexpected admission ceiling")
        require(row["sourceBytes"] == row["width"] ** 2 * (3 if profile == "rgb8" else 2), "Unexpected source capacity")
        live = row["measurement"]["liveIncreaseBytes"]
        if control:
            require(live >= row["sourceBytes"] * row["operations"], "Retained-frame control not detected")
        else:
            require(live < row["sourceBytes"], "Full source frame retained after joined batch")
    return [{"width": size, "records": len([r for r in rows if r["width"] == size]),
             "maximumLiveIncreaseBytes": max(r["measurement"]["liveIncreaseBytes"] for r in rows if r["width"] == size),
             "maximumCumulativeProcessRSSBytes": max(r["measurement"]["processPeakRSSBytes"] for r in rows if r["width"] == size),
             "highWaterFieldUnavailableRecords": sum(r["measurement"]["allZonesHighWaterBytes"] == 0 for r in rows if r["width"] == size)} for size in (257, 1024)]

try:
    report["repositoryRevision"] = run("revision", ["git", "rev-parse", "HEAD"]).strip()
    require(report["repositoryRevision"] == args.revision, "Checkout HEAD differs from requested candidate")
    reference = {}
    for path in report["sourceHashes"]:
        content = subprocess.check_output(["git", "show", args.revision + ":" + path], cwd=repo)
        reference[path] = hashlib.sha256(content).hexdigest()
    require(reference == report["sourceHashes"], "Working source/harness differs from immutable candidate")
    report["sourceHashesMatchCandidate"] = True
    report["sourceReferenceCommand"] = ["git", "show", args.revision + ":<each sourceHashes path>"]
    report["workingTree"] = run("working-tree", ["git", "status", "--porcelain"])
    report["compiler"] = run("compiler", ["xcrun", "swift", "--version"]).strip()
    run("xcode", ["xcodebuild", "-version"])
    run("host", ["sw_vers"])
    command = ["xcrun", "swift", "build", "--package-path", str(repo / "Examples/AppleMemoryProbe"),
               "--scratch-path", str(scratch / "build"), "--build-system", "swiftbuild", "-c", "release", "-j", "2", "--product", "AppleMemoryProbe"]
    run("build", command)
    binary_dir = run("binary-path", command + ["--show-bin-path"]).strip().splitlines()[-1]
    binary = Path(binary_dir) / "AppleMemoryProbe"
    report["binaryPath"] = str(binary)
    report["binarySHA256"] = sha(binary)
    require(source_hashes() == report["sourceHashes"], "Sources changed during build")
    for profile, flags in (("dct12", []), ("rgb8", ["--rgb8"])):
        for control in (False, True):
            label = profile + ("-control" if control else "-baseline")
            text = run(label, [str(binary), *flags, *(["--control-copy"] if control else [])])
            rows = [json.loads(line) for line in text.splitlines()]
            summaries = verify(rows, profile, control)
            report["profiles"].append({"profile": profile, "controlCopy": control, "status": "passed", "records": len(rows), "summary": summaries})
            save()
    require(source_hashes() == report["sourceHashes"], "Sources changed during execution")
    require(sha(binary) == report["binarySHA256"], "Binary changed during execution")
    report["shippingSourcesMatchCandidate"] = all(report["sourceHashes"].get(path) == digest for path, digest in reference.items() if path.startswith("Sources/"))
    report["shippingSourceCount"] = sum(path.startswith("Sources/") for path in reference)
    report["measurements"] = 56
    report["controls"] = 56
    report["status"] = "passed"
except BaseException as error:
    report["status"] = "failed"
    report["failure"] = repr(error)
    raise
finally:
    report["finishedUTC"] = dt.datetime.now(dt.timezone.utc).isoformat()
    save()
print("Apple memory: 56 ordinary-build scopes and 56 retained-frame controls passed.")
