#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Qualify prepared-revision product SBOMs using a completed fresh URL consumer."""
import argparse
import datetime as dt
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def read(path):
    return json.loads(path.read_text())


def write(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2) + "\n")


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--evidence", required=True, type=Path)
parser.add_argument("--repository", required=True, type=Path)
parser.add_argument("--historical", required=True, type=Path)
parser.add_argument("--revision", required=True)
parser.add_argument("--validator-python", required=True, type=Path)
args = parser.parse_args()
if not re.fullmatch(r"[0-9a-f]{40}", args.revision):
    parser.error("--revision must be an immutable full Git commit")
root, repo, historical = (p.resolve() for p in (args.evidence, args.repository, args.historical))
pin = args.revision
receipt_path = root / "product-qualification.json"
if receipt_path.exists() or (root / "cli-raw").exists() or (root / "derived").exists():
    parser.error("Existing product qualification must be preserved; choose fresh evidence")
consumer = read(root / "consumer/report.json")
assert consumer["status"] == "passed" and consumer["candidateRevision"] == pin
assert read(root / "sbom/report.json")["candidateRevision"] == pin
scratch = Path(consumer["scratch"])
checkout = scratch / "consumer-build/checkouts/SwiftJLI"
env = dict(os.environ, **consumer["environmentOverrides"])
report = {"candidateRevision": pin, "startedUTC": now(), "status": "running",
          "helperSHA256": sha(Path(__file__)), "commands": [], "scope":
          "Prepared immutable revision, not stable-tag consumption or publication; library and CLI product SBOMs."}


def run(label, command, dest=root, cwd=checkout, expected=0, timeout=1200):
    dest.mkdir(parents=True, exist_ok=True)
    stdout, stderr = dest / (label + ".stdout"), dest / (label + ".stderr")
    if stdout.exists() or stderr.exists():
        raise RuntimeError("Refusing to overwrite command output: " + label)
    entry = {"label": label, "argv": [str(x) for x in command], "cwd": str(cwd),
             "startedUTC": now(), "timeoutSeconds": timeout,
             "stdout": str(stdout.relative_to(root)), "stderr": str(stderr.relative_to(root))}
    report["commands"].append(entry)
    write(receipt_path, report)
    print(label, flush=True)
    try:
        with stdout.open("wb") as out, stderr.open("wb") as err:
            result = subprocess.run(entry["argv"], cwd=cwd, env=env, stdout=out, stderr=err, timeout=timeout)
        entry["exitCode"] = result.returncode
    except BaseException as error:
        entry["error"] = repr(error)
        raise
    finally:
        entry.update(finishedUTC=now(), stdoutSHA256=sha(stdout), stderrSHA256=sha(stderr))
        write(receipt_path, report)
    if result.returncode != expected:
        raise RuntimeError(f"{label}: exit {result.returncode}, expected {expected}")
    return stdout.read_bytes()


def source_hashes():
    return {str(p.relative_to(checkout)): sha(p) for p in sorted((checkout / "Sources").rglob("*.swift"))} | {
        "Package.swift": sha(checkout / "Package.swift")}


try:
    assert run("source-head-before", ["git", "rev-parse", "HEAD"]).decode().strip() == pin
    assert run("source-status-before", ["git", "status", "--porcelain"]) == b""
    before = source_hashes()
    expected = dict(consumer["shippingSourceSHA256"], **{"Package.swift": consumer["manifestSHA256"]})
    assert before == expected
    for path, digest in before.items():
        data = subprocess.check_output(["git", "show", pin + ":" + path], cwd=checkout, env=env)
        assert hashlib.sha256(data).hexdigest() == digest, path
    identity = {"revision": pin, "fetchedCheckout": str(checkout), "sourceSHA256": before,
                "allWorkingSourceMatchesCommit": True, "libraryBaseline": "f548e5048e5c71204c2a2ec4036bf66c4f040285"}
    library_diff = run("library-baseline-diff", ["git", "diff", "--name-only", identity["libraryBaseline"], pin,
                                                "--", "Sources/SwiftJLI", "Package.swift"])
    assert library_diff == b""
    identity["libraryAndManifestMatchBaseline"] = True
    identity["shippingChangesFromBaseline"] = run("shipping-baseline-diff", ["git", "diff", "--name-only",
        identity["libraryBaseline"], pin, "--", "Sources", "Package.swift"]).decode().splitlines()
    assert identity["shippingChangesFromBaseline"] == ["Sources/SwiftJLICLI/main.swift"]
    identity["preparedVersion"] = (checkout / "VERSION").read_text().strip()
    assert identity["preparedVersion"] == "1.1.0"
    write(root / "consumer/source-identity.json", identity)

    old_capture = read(historical / "derived/inputs/receipt.json")
    required_versions = {"jsonschema": "4.25.1", "referencing": "0.37.0", "pyshacl": "0.30.1",
                         "rdflib": "7.1.4", "packageurl-python": "0.17.6"}
    version_code = "import importlib.metadata,json; print(json.dumps({n:importlib.metadata.version(n) for n in " + repr(list(required_versions)) + "}))"
    versions = json.loads(run("validator-versions", [args.validator_python, "-c", version_code], cwd=repo))
    assert versions == required_versions
    run("validator-packages", [args.validator_python, "-m", "pip", "freeze", "--all"], cwd=repo)
    cli = root / "cli-raw"
    cli.mkdir()
    cli_report = {"candidateRevision": pin, "product": "swiftjli-cli", "preparedVersion": identity["preparedVersion"],
                  "startedUTC": now(), "buildEngine": "swiftbuild", "jobs": 2,
                  "sourceSHA256": before, "environmentOverrides": consumer["environmentOverrides"], "commands": []}
    common = ["xcrun", "swift", "build", "--package-path", str(checkout), "--scratch-path", str(scratch / "sbom-build"),
              "--cache-path", str(scratch / "package-cache"), "--config-path", str(scratch / "configuration"),
              "--security-path", str(scratch / "security"), "--disable-dependency-cache",
              "--build-system", "swiftbuild", "-j", "2", "-c", "release", "--product", "swiftjli-cli"]
    for spec in ("spdx", "cyclonedx"):
        run("build-" + spec, common + ["--sbom-spec", spec, "--sbom-output-dir", str(cli / spec), "--sbom-filter", "all"], dest=cli)
        cli_report["commands"].append(report["commands"][-1])
    binary_dir = run("binary-path", common + ["--show-bin-path"], dest=cli).decode().strip().splitlines()[-1]
    binary = Path(binary_dir) / "swiftjli-cli"
    cli_report["binary"] = {"path": str(binary), "sha256": sha(binary)}
    assert run("binary-version", [binary, "--version"], dest=cli).decode().strip() == "swiftjli-cli 1.1.0"
    for label, flag in (("native-linkage", "-L"), ("native-load-commands", "-l")):
        run(label, ["/usr/bin/otool", flag, binary], dest=cli)
        cli_report["commands"].append(report["commands"][-1])
    cli_report["rawSBOMs"] = {str(p.relative_to(cli)): sha(p) for spec in ("spdx", "cyclonedx") for p in (cli / spec).glob("*.json")}
    assert len(cli_report["rawSBOMs"]) == 2
    cli_report.update(status="generation_passed", finishedUTC=now(), sourceAndCheckoutUnchanged=source_hashes() == before)
    assert cli_report["sourceAndCheckoutUnchanged"]
    write(cli / "report.json", cli_report)

    # Reuse pinned official files, preserving historical provenance rather than re-downloading.
    inputs = root / "derived/inputs"
    inputs.mkdir(parents=True)
    capture = {"revision": pin, "capturedUTC": now(), "files": [], "commands": [],
               "validatorPython": str(args.validator_python), "validatorVersions": versions,
               "reusedOfficialProvenance": {"path": str(historical / "derived/inputs/receipt.json"),
                   "sha256": sha(historical / "derived/inputs/receipt.json"),
                   "notice": "Historical source/binary entries are not current qualification; only individually hash-checked official validation files are reused."}}
    shutil.copy2(historical / "derived/inputs/receipt.json", inputs / "historical-official-provenance.json")
    source_paths = ["LICENSE", "NOTICE", "Package.swift", "VERSION", "ManPages/swiftjli-cli.1", "Sources/SwiftJLICLI/main.swift",
                    "Documentation/Migration/provenance.json", "Documentation/Migration/Fixtures/ICC-LICENSE.txt",
                    "Documentation/Migration/Fixtures/sRGB2014.icc", "Sources/SwiftJLI/Native/ColorSpace/SRGBICCProfile.swift"]
    for path in source_paths:
        label = "source-command-" + path.replace("/", "_")
        data = run(label, ["git", "show", pin + ":" + path], dest=inputs)
        captured = inputs / "source" / path
        captured.parent.mkdir(parents=True, exist_ok=True)
        captured.write_bytes(data)
        assert captured.read_bytes() == (checkout / path).read_bytes()
        capture["commands"].append(report["commands"][-1])
    for entry in old_capture["files"]:
        if entry["path"].startswith("official/"):
            original = historical / "derived/inputs" / entry["path"]
            assert sha(original) == entry["sha256"]
            copied = inputs / entry["path"]
            copied.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, copied)
            if "uncompressedSHA256" in entry:
                assert hashlib.sha256(gzip.decompress(copied.read_bytes())).hexdigest() == entry["uncompressedSHA256"]
    release_binary = Path(consumer["binaries"]["release"]["path"])
    consumer_hash = consumer["binaries"]["release"]["sha256"]
    assert sha(release_binary) == consumer_hash
    capture["observedBinary"] = {"path": str(release_binary), "sha256": consumer_hash}
    for label, command in (("native-linkage", ["/usr/bin/otool", "-L", release_binary]),
                           ("native-load-commands", ["/usr/bin/otool", "-l", release_binary]),
                           ("host-os", ["/usr/bin/sw_vers"]),
                           ("sdk-version", ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-version"]),
                           ("sdk-build", ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-build-version"])):
        run(label, command, dest=inputs)
        capture["commands"].append(report["commands"][-1])
    capture["binaryUnchanged"] = sha(release_binary) == consumer_hash
    assert capture["binaryUnchanged"]
    capture["files"] = [{"path": str(p.relative_to(inputs)), "sha256": sha(p), "bytes": p.stat().st_size}
                        for p in sorted(inputs.rglob("*")) if p.is_file()]
    write(inputs / "receipt.json", capture)
    for raw in (root / "sbom", cli):
        schema_dir = raw / "schemas"
        schema_dir.mkdir(exist_ok=False)
        reuse = {"source": str(historical / "sbom/schemas"), "sourceSetupReceiptSHA256": sha(historical / "sbom/schema-setup.json"),
                 "files": [], "licences": "../../schema-licences/README.md (relative to this qualification's root)",
                 "downloadedAgain": False}
        for original in sorted((historical / "sbom/schemas").glob("*.gz")):
            copied = schema_dir / original.name
            shutil.copy2(original, copied)
            assert sha(copied) == sha(original)
            reuse["files"].append({"path": copied.name, "sha256": sha(copied),
                                  "uncompressedSHA256": hashlib.sha256(gzip.decompress(copied.read_bytes())).hexdigest()})
        assert len(reuse["files"]) == 4
        write(raw / "schema-reuse.json", reuse)
        shutil.copy2(historical / "sbom/schema-setup.json", raw / "historical-schema-provenance.json")
        run("schema-validation", [args.validator_python, root / "helpers/sbom-validate.py", "--evidence", raw],
            dest=raw, cwd=repo, expected=1)
        results = read(raw / "schema-results.json")["records"]
        assert [(x["status"], len(x["errors"])) for x in results] == [("failed", 2), ("passed", 0)]
        run("field-audit", [args.validator_python, root / "helpers/sbom-audit.py", "--evidence", raw], dest=raw, cwd=repo)

    for product, output in (("SwiftJLI", "library"), ("swiftjli-cli", "cli")):
        command = [args.validator_python, root / "helpers/derive-prepared.py", "--revision", pin,
                   "--evidence", root, "--inputs", inputs, "--product", product, "--output", root / "derived" / output]
        if product == "swiftjli-cli":
            command += ["--raw-sbom", cli]
        run("derive-" + output, command, cwd=repo)
        write(root / "derived" / output / "execution.json", report["commands"][-1])
    assert run("source-head-after", ["git", "rev-parse", "HEAD"]).decode().strip() == pin
    assert run("source-status-after", ["git", "status", "--porcelain"]) == b""
    assert source_hashes() == before
    assert sha(binary) == cli_report["binary"]["sha256"] and sha(release_binary) == consumer_hash
    report.update(status="passed", finishedUTC=now(), sourceAndBinariesUnchanged=True,
                  validatorVersions=versions, rawSPDXSchema="failed: two producer records per product",
                  rawCycloneDXSchema="passed", derivedProducts={p: read(root / "derived" / p / "receipt.json")["status"] for p in ("library", "cli")})
    write(receipt_path, report)
except BaseException as error:
    report.update(status="failed", failure=repr(error), finishedUTC=now())
    write(receipt_path, report)
    raise
