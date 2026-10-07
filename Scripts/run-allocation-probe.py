#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run the Linux/glibc decoder allocation experiment, including its positive control."""
import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check(condition, message):
    if not condition:
        raise RuntimeError(message)


def validate(rows, control):
    check(len(rows) == 61 and rows[0]["cPassed"], "Missing records or calibration")
    calibration = rows[0]
    large = [b["requestedBytes"] for b in calibration["measurement"]["allocationSizes"]
             if b["requestedBytes"] >= calibration["swiftByteCount"]]
    check(len(large) == 1, "Ambiguous Swift array header calibration")
    header = large[0] - calibration["swiftByteCount"]
    check(0 <= header <= 256, "Unexpected Swift storage allocation shape")
    seen = set()
    for r in rows[1:]:
        key = (r["width"], r["profile"], r["entry"], r["repetition"])
        check(key not in seen, "Duplicate measurement")
        seen.add(key)
        m = r["measurement"]
        check(r["samplesMatch"] and r["controlCopy"] == control and m["overflow"] == 0,
              "Failed sample/control/allocator check")
        sizes = {b["requestedBytes"]: b["count"] for b in m["allocationSizes"]}
        # Packed frame allocation only occurs in allocating decode; a supplied
        # padded destination predates the scope. Its deliberate copy adds one.
        expected = int(r["entry"] == "allocating") + int(control)
        check(sizes.get(r["destinationCapacity"] + header, 0) == expected,
              f"Unexpected final-frame-size allocations: {key}")
        if r["entry"] == "callerDestination":
            check(sizes.get(r["logicalPixelBytes"] + header, 0) == 0,
                  f"Unexpected packed intermediate-frame allocation: {key}")
    expected_keys = {(size, profile, entry, repetition)
                     for size in [257, 1024]
                     for profile in ["lossless16", "dct12", "rgb8", "xyb8", "xybFloat32"]
                     for entry in ["allocating", "callerDestination"] for repetition in range(3)}
    check(seen == expected_keys, "Profile matrix incomplete")
    return header


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=pathlib.Path)
    parser.add_argument("--docker-image", default="swift:6.4-noble")
    args = parser.parse_args()
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=False)
    image = subprocess.check_output(["docker", "image", "inspect", args.docker_image,
                                    "--format", "{{.Id}}"], text=True).strip()
    manifest = {"status": "running", "image": image,
                "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "workingTree": subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True),
                "sourceHashes": {}, "commands": []}
    for path in [ROOT / "Package.swift", pathlib.Path(__file__),
                 *sorted((ROOT / "Sources").rglob("*.swift")),
                 *sorted((ROOT / "Examples/AllocationProbe").rglob("*"))]:
        if path.is_file() and ".build" not in path.parts:
            manifest["sourceHashes"][str(path.relative_to(ROOT))] = sha(path)

    def run(command, label, timeout=300):
        name = "swiftjli-heap-" + uuid.uuid4().hex[:12]
        cmd = ["docker", "run", "--rm", "--name", name, "--cpus", "1", "--memory", "1g",
               "--ulimit", "core=0", "-v", f"{ROOT}:/src", "-w", "/src", image, *command]
        record = {"command": cmd}
        manifest["commands"].append(record)
        try:
            with (out / (label + ".stdout")).open("w") as stdout, (out / (label + ".stderr")).open("w") as stderr:
                result = subprocess.run(cmd, stdout=stdout, stderr=stderr, timeout=timeout)
            record["exitCode"] = result.returncode
            check(result.returncode == 0, f"{label} exited {result.returncode}")
        finally:
            subprocess.run(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        run(["swift", "--version"], "compiler")
        run(["swift", "build", "--package-path", "Examples/AllocationProbe", "--scratch-path",
             ".build-allocation-probe", "-c", "release", "-j", "2"], "build")
        binary = ROOT / ".build-allocation-probe/release/AllocationProbe"
        manifest["binarySHA256"] = sha(binary)
        run(["/src/.build-allocation-probe/release/AllocationProbe"], "baseline")
        run(["/src/.build-allocation-probe/release/AllocationProbe", "--control-copy"], "control")
        baseline = [json.loads(s) for s in (out / "baseline.stdout").read_text().splitlines()]
        control = [json.loads(s) for s in (out / "control.stdout").read_text().splitlines()]
        header = validate(baseline, False)
        check(validate(control, True) == header, "Calibration changed between runs")
        manifest["arrayHeaderRequestedBytes"] = header
        manifest["summary"] = []
        for size, profile, entry in sorted({(r["width"], r["profile"], r["entry"]) for r in baseline[1:]}):
            group = [r for r in baseline[1:] if (r["width"], r["profile"], r["entry"]) == (size, profile, entry)]
            manifest["summary"].append({"width": size, "height": size, "profile": profile, "entry": entry,
                "repetitions": len(group), "logicalPixelBytes": group[0]["logicalPixelBytes"],
                "medianPeakRequestedBytes": statistics.median(r["measurement"]["peakRequestedBytes"] for r in group),
                "medianLiveRequestedBytes": statistics.median(r["measurement"]["liveRequestedBytes"] for r in group)})
        manifest["status"] = "passed"
    except BaseException as error:
        manifest["status"] = "failed"
        manifest["error"] = repr(error)
        raise
    finally:
        manifest["logHashes"] = {p.name: sha(p) for p in sorted(out.iterdir()) if p.is_file()}
        (out / "results.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"status": manifest["status"], "decodeMeasurements": 60,
                      "positiveControls": 60, "arrayHeaderRequestedBytes": header}))


if __name__ == "__main__":
    main()
