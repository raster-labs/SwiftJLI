#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Retain upstream licence texts and exact provenance for qualification schemas."""
import argparse
import gzip
import hashlib
import json
import subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--milestone", required=True, type=Path)
p.add_argument("--output", required=True, type=Path)
a = p.parse_args()
out = a.output.resolve()
out.mkdir(parents=True, exist_ok=False)
base = a.milestone.resolve()
records = []
def sha(data):
    return hashlib.sha256(data).hexdigest()
def fetch(name, url, role):
    data = subprocess.check_output(["curl", "--fail", "--location", "--silent", "--show-error", "--connect-timeout", "10", "--max-time", "45", url], timeout=50)
    (out / name).write_bytes(data)
    records.append({"path": name, "url": url, "sha256": sha(data), "bytes": len(data), "role": role})
fetch("CycloneDX-LICENSE", "https://raw.githubusercontent.com/CycloneDX/specification/1ce97b2a7b8cf2429da248560d2aa671c6bce74a/LICENSE", "Exact pinned CycloneDX schema repository Apache-2.0 licence and OWASP copyright")
fetch("SPDX-SPEC-LICENSE", "https://raw.githubusercontent.com/spdx/spdx-spec/61a7a341f2533d6e084c48c88463da63f05e1af0/LICENSE", "SPDX specification repository licence record; not an asserted source revision for the differently hashed published schema")
fetch("SPDX-MODEL-LICENSE.md", "https://raw.githubusercontent.com/spdx/spdx-3-model/a745f63e8643d5ae0f0851fcfa6836085308f80b/License.md", "SPDX3.0.1 model licence at its peeled release tag; official model also declares Community-Spec-1.0")
capture = json.loads((base / "final-consumer-sbom/derived/inputs/receipt.json").read_text())
purl = next(x for x in capture["downloads"] if "swift-definition" in x["file"])
fetch("PURL-SPEC-LICENSE", "https://raw.githubusercontent.com/package-url/purl-spec/" + purl["repositoryRevision"] + "/LICENSE", "Exact source licence for retained Swift package URL definition")
covered = []
for location in ("sbom/schemas", "final-consumer-sbom/sbom/schemas"):
    for path in sorted((base / location).glob("*.gz")):
        raw = gzip.decompress(path.read_bytes())
        covered.append({"path": str(path.relative_to(base)), "sha256": sha(raw), "gzipSHA256": sha(path.read_bytes())})
for location in ("final-consumer-sbom/derived/inputs", "final-consumer-sbom/derived/inputs-attempt-1"):
    for path in sorted((base / location / "official").glob("*.gz")):
        raw = gzip.decompress(path.read_bytes())
        covered.append({"path": str(path.relative_to(base)), "sha256": sha(raw), "gzipSHA256": sha(path.read_bytes())})
receipt = {"licenceFiles": records, "coveredSchemasAndModels": covered,
    "sourceLimit": "The published SPDX3.0.1 JSON Schema is identified by its canonical publisher URL and SHA-256. The inspected SPDX source repository commit contains a different schema blob and is cited only for its specification licence, not as byte-identical schema provenance.",
    "helperSHA256": sha(Path(__file__).read_bytes())}
(out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps({"status": "captured", "licenceFiles": len(records), "coveredCopies": len(covered)}))
