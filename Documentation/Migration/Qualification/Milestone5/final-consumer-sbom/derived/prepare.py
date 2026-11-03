#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Capture immutable source, official validation inputs and observed native linkage."""
import argparse
import datetime
import gzip
import hashlib
import json
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

PIN = "f548e5048e5c71204c2a2ec4036bf66c4f040285"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--repository", type=Path, required=True)
parser.add_argument("--evidence", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
root = args.output.resolve()
root.mkdir(parents=True, exist_ok=False)
repo = args.repository.resolve()
evidence = args.evidence.resolve()
receipt = {"capturedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
           "revision": PIN, "commands": [], "files": [], "downloads": []}
def sha(data):
    return hashlib.sha256(data).hexdigest()
def save(name, data, **metadata):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    receipt["files"].append({"path": name, "sha256": sha(data), "bytes": len(data), **metadata})
def command(argv, name, cwd=repo):
    p = subprocess.run(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    save(name + ".stdout", p.stdout)
    save(name + ".stderr", p.stderr)
    receipt["commands"].append({"argv": argv, "cwd": str(cwd), "exitCode": p.returncode,
                                "stdout": name + ".stdout", "stderr": name + ".stderr"})
    p.check_returncode()
    return p.stdout
for name in ("LICENSE", "NOTICE", "Package.swift", "Documentation/Migration/provenance.json",
             "Documentation/Migration/Fixtures/ICC-LICENSE.txt", "Documentation/Migration/Fixtures/sRGB2014.icc",
             "Sources/SwiftJLI/Native/ColorSpace/SRGBICCProfile.swift"):
    data = command(["git", "show", PIN + ":" + name], "source-command-" + name.replace("/", "_"))
    save("source/" + name, data, sourceRevision=PIN, sourcePath=name)
for name, url in (
    ("spdx-model.ttl", "https://spdx.org/rdf/3.0.1/spdx-model.ttl"),
    ("spdx-context.jsonld", "https://spdx.org/rdf/3.0.1/spdx-context.jsonld"),
):
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read()
        final_url = response.url
    save("official/" + name + ".gz", gzip.compress(data, mtime=0), uncompressedSHA256=sha(data), url=url)
    receipt["downloads"].append({"url": url, "finalURL": final_url, "file": "official/" + name + ".gz", "sha256": sha(data)})
# Capture the normative Swift package-URL type at a commit, not a moving branch.
purl_pin = command(["git", "ls-remote", "https://github.com/package-url/purl-spec.git", "refs/heads/main"], "purl-spec-revision").decode().split()[0]
url = "https://raw.githubusercontent.com/package-url/purl-spec/" + purl_pin + "/types/swift-definition.json"
with urllib.request.urlopen(url, timeout=60) as response:
    data = response.read()
save("official/swift-definition.json", data, url=url, repositoryRevision=purl_pin)
receipt["downloads"].append({"url": url, "file": "official/swift-definition.json", "sha256": sha(data), "repositoryRevision": purl_pin})
consumer = json.loads((evidence / "consumer/report.json").read_text())
assert consumer["candidateRevision"] == PIN
binary = consumer["binaries"]["release"]
assert sha(Path(binary["path"]).read_bytes()) == binary["sha256"]
receipt["observedBinary"] = binary
command(["/usr/bin/otool", "-L", binary["path"]], "native-linkage")
command(["/usr/bin/otool", "-l", binary["path"]], "native-load-commands")
command(["/usr/bin/sw_vers"], "host-os")
command(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-version"], "sdk-version")
command(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-build-version"], "sdk-build")
assert sha(Path(binary["path"]).read_bytes()) == binary["sha256"]
receipt["binaryUnchanged"] = True
venv = Path(tempfile.mkdtemp(prefix="swiftjli-m5-derived-sbom-", dir="/private/tmp")) / "venv"
command([sys.executable, "-m", "venv", str(venv)], "validator-venv")
python = str(venv / "bin/python")
command([python, "-m", "pip", "install", "--disable-pip-version-check", "jsonschema==4.25.1",
         "referencing==0.37.0", "pyshacl==0.30.1", "rdflib==7.1.4", "packageurl-python==0.17.6"], "validator-install")
command([python, "-m", "pip", "freeze", "--all"], "validator-packages")
receipt["validatorPython"] = python
receipt["helperSHA256"] = sha(Path(__file__).read_bytes())
(root / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps({"status": "captured", "validatorPython": python, "files": len(receipt["files"])}))
