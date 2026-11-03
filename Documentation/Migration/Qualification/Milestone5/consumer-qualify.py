#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fresh GitHub consumer and build-associated SBOM evidence, without editing source."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

PIN = "8ae2762710d6279cd92222f5bb5ca95f042f694e"
URL = "https://github.com/raster-labs/SwiftJLI.git"

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    consumer_evidence = evidence / "consumer"
    sbom_evidence = evidence / "sbom"
    consumer_evidence.mkdir(parents=True, exist_ok=False)
    sbom_evidence.mkdir(parents=True, exist_ok=False)
    scratch = Path(tempfile.mkdtemp(prefix="swiftjli-m5-consumer-", dir="/private/tmp"))
    package = scratch / "consumer"
    sources = package / "Sources/IndependentConsumer"
    sources.mkdir(parents=True)
    repo = Path(__file__).resolve().parents[4]
    historical = repo / "Documentation/Migration/Qualification/NonWatchCompletion/Harnesses/completion-url-consumer"
    manifest = (historical / "Package.swift").read_text().replace("e7e54f756cccec07a66870ebefd68b5bbb5c79a6", PIN)
    (package / "Package.swift").write_text(manifest)
    shutil.copy2(historical / "Sources/IndependentConsumer/main.swift", sources / "main.swift")
    env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer",
               CLANG_MODULE_CACHE_PATH=str(scratch / "clang-cache"),
               SWIFTPM_MODULECACHE_OVERRIDE=str(scratch / "swift-cache"),
               GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
    report = {"candidateRevision": PIN, "repositoryURL": URL, "contract": "0.10.0",
              "scratch": str(scratch), "startedUTC": dt.datetime.now(dt.timezone.utc).isoformat(),
              "commands": [], "status": "running", "buildEngine": "swiftbuild", "jobs": 2,
              "sourceOfConsumer": str(historical.relative_to(repo)),
              "environmentOverrides": {k: env[k] for k in ("DEVELOPER_DIR", "CLANG_MODULE_CACHE_PATH", "SWIFTPM_MODULECACHE_OVERRIDE", "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL")}}
    current = consumer_evidence

    def save():
        (current / "report.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(label, command, cwd=package, timeout=1200):
        log = current / (label + ".log")
        entry = {"label": label, "command": command, "cwd": str(cwd), "log": log.name,
                 "startedUTC": dt.datetime.now(dt.timezone.utc).isoformat()}
        report["commands"].append(entry)
        save()
        print(label, flush=True)
        try:
            with log.open("w") as output:
                result = subprocess.run(command, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
            entry["exitCode"] = result.returncode
        except BaseException as error:
            entry["error"] = repr(error)
            raise
        finally:
            entry["finishedUTC"] = dt.datetime.now(dt.timezone.utc).isoformat()
            entry["logSHA256"] = digest(log)
            save()
        if result.returncode:
            raise RuntimeError(f"{label} failed with exit {result.returncode}; see {log}")
        return log.read_text()

    def flags(path, build):
        return ["--package-path", str(path), "--scratch-path", str(build),
                "--cache-path", str(scratch / "package-cache"), "--config-path", str(scratch / "configuration"),
                "--security-path", str(scratch / "security"), "--disable-dependency-cache"]

    try:
        run("compiler", ["xcrun", "swift", "--version"])
        run("xcode", ["xcodebuild", "-version"])
        run("host", ["sw_vers"])
        consumer_build = scratch / "consumer-build"
        common = flags(package, consumer_build)
        run("resolve", ["xcrun", "swift", "package", *common, "resolve"])
        resolved = json.loads((package / "Package.resolved").read_text())
        pins = resolved["pins"]
        if len(pins) != 1 or pins[0]["location"] != URL or pins[0]["state"]["revision"] != PIN:
            raise RuntimeError("Unexpected dependency graph or resolved revision")
        report["resolvedPins"] = pins
        checkout = consumer_build / "checkouts/SwiftJLI"
        actual = run("checkout-revision", ["git", "rev-parse", "HEAD"], checkout).strip()
        if actual != PIN:
            raise RuntimeError("Fetched checkout revision mismatch")
        run("checkout-status", ["git", "status", "--porcelain"], checkout)
        report["shippingSourceSHA256"] = {str(p.relative_to(checkout)): digest(p) for p in sorted((checkout / "Sources").rglob("*.swift"))}
        report["manifestSHA256"] = digest(checkout / "Package.swift")
        for config in ("debug", "release"):
            command = ["xcrun", "swift", "build", *common, "--build-system", "swiftbuild", "-j", "2", "-c", config, "--product", "IndependentConsumer"]
            run(config + "-clean-build", command)
            run(config + "-incremental-build", command)
            binary_dir = run(config + "-binary-path", command + ["--show-bin-path"]).strip().splitlines()[-1]
            binary = Path(binary_dir) / "IndependentConsumer"
            report.setdefault("binaries", {})[config] = {"path": str(binary), "sha256": digest(binary)}
            run(config + "-run", [str(binary)])
        shutil.copy2(package / "Package.swift", consumer_evidence / "Package.swift")
        shutil.copy2(package / "Package.resolved", consumer_evidence / "Package.resolved")
        shutil.copy2(sources / "main.swift", consumer_evidence / "main.swift")
        report["consumerSourceSHA256"] = digest(sources / "main.swift")
        report["status"] = "passed"
        report["finishedUTC"] = dt.datetime.now(dt.timezone.utc).isoformat()
        save()
        consumer_report = report
        current = sbom_evidence
        report = {"candidateRevision": PIN, "repositoryURL": URL, "contract": "0.10.0", "status": "running",
                  "startedUTC": dt.datetime.now(dt.timezone.utc).isoformat(), "commands": [], "sboms": [],
                  "buildEngine": "swiftbuild", "jobs": 2, "scratch": str(scratch),
                  "shippingSourceSHA256": consumer_report["shippingSourceSHA256"],
                  "environmentOverrides": consumer_report["environmentOverrides"]}
        for spec in ("spdx", "cyclonedx"):
            destination = sbom_evidence / spec
            output = run("build-" + spec, ["xcrun", "swift", "build", *flags(checkout, scratch / "sbom-build"),
                "--build-system", "swiftbuild", "-j", "2", "-c", "release", "--product", "SwiftJLI",
                "--sbom-spec", spec, "--sbom-output-dir", str(destination), "--sbom-filter", "all"], checkout)
            files = sorted(destination.glob("*.json"))
            if not files:
                raise RuntimeError("No build-associated " + spec + " SBOM emitted")
            for path in files:
                json.loads(path.read_text())
                report["sboms"].append({"path": str(path.relative_to(sbom_evidence)), "sha256": digest(path), "buildAssociated": True})
            if "skipping SBOM validation" in output:
                report.setdefault("openGates", []).append(spec + ": producer schema validation skipped; independent validation required")
        report["status"] = "generation_passed_schema_validation_pending"
        report["finishedUTC"] = dt.datetime.now(dt.timezone.utc).isoformat()
        save()
    except BaseException as error:
        report["status"] = "failed"
        report["failure"] = repr(error)
        report["finishedUTC"] = dt.datetime.now(dt.timezone.utc).isoformat()
        save()
        raise

if __name__ == "__main__":
    main()
