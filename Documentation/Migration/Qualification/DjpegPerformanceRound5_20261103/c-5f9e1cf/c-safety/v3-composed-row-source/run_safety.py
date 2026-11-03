#!/usr/bin/env python3
"""Print the planned command by default; --execute requires a granted CPU slot."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=["row"], required=True)
    parser.add_argument("--receipt-dir", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    manifest = json.loads((root / "source-manifest.json").read_text())
    target = manifest["targets"][args.target]
    output = args.receipt_dir.resolve()
    command = [
        "xcrun", "clang", "-O2", "-g", "-std=c11", "-Wall", "-Wextra", "-Werror",
        "-fsanitize=address,undefined", "-fno-sanitize-recover=all",
        "-I", str(root / args.target / "include"), "-I", str(root),
        str(root / (args.target + "_safety.c")),
        str(root / args.target / "ACBlock.c"),
        str(root / args.target / "LosslessRow.c"),
        str(root / args.target / "LosslessCodeZeroRow.c"),
        "-o", str(output / "safety-harness"),
    ]
    if not args.execute:
        print(json.dumps({"status": "NOT EXECUTED", "target": args.target,
                          "sourceRevision": target["sourceRevision"], "command": command}, indent=2))
        return 0
    # Never replace an earlier receipt or binaries. Source hashes are checked
    # before compilation, so an edited harness requires a new version manifest.
    if output.exists():
        parser.error("receipt directory already exists; choose a new versioned path")
    for entry in manifest["files"]:
        path = root / entry["path"]
        if sha(path) != entry["sha256"]:
            parser.error("source hash changed: " + entry["path"])
    output.mkdir(parents=True)
    env = os.environ.copy()
    env.update(DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer",
               ASAN_OPTIONS="halt_on_error=1", UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1")
    receipt = {
        "target": args.target, "sourceRevision": target["sourceRevision"],
        "sourceManifestSHA256": sha(root / "source-manifest.json"),
        "compileCommand": command, "cwd": str(root),
        "environmentOverrides": {key: env[key] for key in
                                 ["DEVELOPER_DIR", "ASAN_OPTIONS", "UBSAN_OPTIONS"]},
        "startedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "scope": "bounded standalone memory/undefined-behaviour diagnostic; not performance acceptance",
    }
    version = subprocess.run(["xcrun", "clang", "--version"], env=env,
                             text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (output / "clang-version.txt").write_text(version.stdout)
    receipt["compilerVersionExitCode"] = version.returncode
    with (output / "compile.log").open("w") as log:
        compiled = subprocess.run(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
    receipt["compileExitCode"] = compiled.returncode
    exit_code = compiled.returncode
    if compiled.returncode == 0:
        binary = output / "safety-harness"
        receipt["binarySHA256"] = sha(binary)
        receipt["runCommand"] = [str(binary)]
        start = time.monotonic()
        with (output / "results.json").open("w") as stdout, (output / "stderr.log").open("w") as stderr:
            run = subprocess.run([str(binary)], cwd=root, env=env, stdout=stdout, stderr=stderr)
        receipt.update(runExitCode=run.returncode, runElapsedSeconds=time.monotonic() - start)
        exit_code = run.returncode
        if run.returncode == 0:
            try:
                result = json.loads((output / "results.json").read_text())
                assert result["allChecksPassed"] is True
                assert result["randomCases"] >= 1048576
                assert sum(result["statusCounts"]) == result["cases"]
                assert sum(result[k] for k in ["randomCases", "boundaryCases", "knownCases",
                                               "aliasCases", "invalidArgumentCases"]) == result["cases"]
                assert all(result["availableBitCounts"])
                assert all(result["categoryCounts"][i] for i in range(17))
                if args.target == "row":
                    assert result["aliasCases"] >= 10000
                receipt["counterValidation"] = "passed"
            except (AssertionError, KeyError, ValueError) as error:
                receipt["counterValidation"] = "failed: " + repr(error)
                exit_code = 1
    receipt["finishedUTC"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (output / "command-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
