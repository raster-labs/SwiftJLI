#!/usr/bin/env python3
"""Prove shared-DCT storage tests detect stride/endian bugs (TEST-09).

Runs only in a disposable source copy; never mutates the repository. Requires
Swift Testing (full Xcode or a Linux Swift toolchain). Logs and JSON evidence
are retained under --output-dir. A compile failure is not a killed mutation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--docker-image", help="Run Swift in this Linux container instead of on the host")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    target = Path("Sources/SwiftJLI/Native/Contract/SharedDCTStorage.swift")
    original = (root / target).read_text()
    mutations = {
        "encode-packed-stride": (
            "let offset = row * source.rowBytes, out = row * width",
            "let offset = row * width * components * bps, out = row * width"),
        "encode-big-endian": (
            "Float(Int(source.bytes[p]) | (Int(source.bytes[p + 1]) << 8))",
            "Float((Int(source.bytes[p]) << 8) | Int(source.bytes[p + 1]))"),
        "decode-packed-stride": (
            "let offset = row * destination.rowBytes + (x * nc + c) * bps",
            "let offset = (row * width * nc + x * nc + c) * bps"),
        "decode-big-endian": (
            "if bps == 2 { destination.bytes[offset + 1] = UInt8(value >> 8) }",
            "if bps == 2 { destination.bytes[offset] = UInt8(value >> 8); destination.bytes[offset + 1] = UInt8(truncatingIfNeeded: value) }"),
    }
    for name, (before, _) in mutations.items():
        if original.count(before) != 1:
            raise SystemExit(f"Mutation anchor changed: {name}; review the source")
    evidence = {
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "platform": platform.platform(),
        "compiler": subprocess.check_output(
            (["docker", "run", "--rm", args.docker_image] if args.docker_image else [])
            + ["swift", "--version"], text=True).strip(),
        "source_sha256": hashlib.sha256(original.encode()).hexdigest(),
        "test_sha256": hashlib.sha256((root / "Tests/SwiftJLITests/Native/SharedDCTStorageTests.swift").read_bytes()).hexdigest(),
        "results": [],
    }
    with tempfile.TemporaryDirectory(prefix="swiftjli-mutations-", dir=output) as temporary:
        checkout = Path(temporary)
        shutil.copy2(root / "Package.swift", checkout)
        for folder in ("Sources", "Tests"):
            shutil.copytree(root / folder, checkout / folder)
        command = ["swift", "test", "--jobs", "4", "--filter", "SharedDCTStorageTests"]
        if args.docker_image:
            evidence["container_image"] = subprocess.check_output(
                ["docker", "image", "inspect", args.docker_image, "--format", "{{.Id}}"], text=True).strip()
            command = ["docker", "run", "--rm", "--ulimit", "core=0",
                "-v", f"{checkout}:/package", "-w", "/package", args.docker_image] + command
        evidence["command"] = command
        variants = {"baseline": original}
        variants.update({name: original.replace(before, after) for name, (before, after) in mutations.items()})
        for name, contents in variants.items():
            (checkout / target).write_text(contents)
            log = output / f"{name}.log"
            with log.open("w") as stream:
                result = subprocess.run(command, cwd=checkout, stdout=stream,
                    stderr=subprocess.STDOUT, timeout=600, env={**os.environ, "NO_COLOR": "1"})
            text = log.read_text()
            issues = re.search(r"Test run with \d+ tests? in \d+ suites? failed .* with (\d+) issues?", text)
            count = int(issues.group(1)) if issues else 0
            assertions = text.count("Expectation failed")
            passed = (result.returncode == 0 and "Test run with 1 test in 1 suite passed" in text
                if name == "baseline" else result.returncode != 0 and count > 0 and assertions > 0)
            evidence["results"].append({"name": name, "exit_code": result.returncode,
                "issues": count, "expectation_failure_messages": assertions,
                "caught_error_messages": text.count("Caught error"),
                "mutated_source_sha256": hashlib.sha256(contents.encode()).hexdigest(),
                "expected_outcome_observed": passed, "log": log.name})
            (output / "results.json").write_text(json.dumps(evidence, indent=2) + "\n")
            print(f"{name}: exit {result.returncode}, {count} issues, accepted={passed}", flush=True)
            if not passed:
                raise SystemExit(f"Unexpected result for {name}; inspect {log}")
    print("Storage mutation checks passed: baseline succeeds; all four mutants fail assertions.")


if __name__ == "__main__":
    main()
