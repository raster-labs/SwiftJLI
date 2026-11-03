#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Record producer field findings separately from JSON Schema results."""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--evidence", type=Path, required=True)
args = parser.parse_args()
root = args.evidence.resolve()
pin = json.loads((root / "report.json").read_text())["candidateRevision"]
records = []
for spec in ("spdx", "cyclonedx"):
    for path in sorted((root / spec).glob("*.json")):
        document = json.loads(path.read_text())
        row = {"file": str(path.relative_to(root)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "findings": []}
        if spec == "cyclonedx":
            references = defaultdict(list)
            def visit(value, pointer=""):
                if isinstance(value, dict):
                    if "bom-ref" in value:
                        references[value["bom-ref"]].append(pointer + "/bom-ref")
                    for key, child in value.items():
                        visit(child, pointer + "/" + key.replace("~", "~0").replace("/", "~1"))
                elif isinstance(value, list):
                    for index, child in enumerate(value):
                        visit(child, pointer + "/" + str(index))
            visit(document)
            row["findings"] += [{"kind": "duplicate_bom_ref", "value": name, "paths": paths} for name, paths in references.items() if len(paths) > 1]
            packages = document["components"]
            row["componentVersionsMatchCandidate"] = all(p.get("version") == pin for p in packages)
            row["declaredComponents"] = [{"name": p["name"], "version": p.get("version"), "type": p.get("type")} for p in packages]
            row["coreProductLicenceFieldPresent"] = "licenses" in document["metadata"]["component"]
            row["dependencyGraph"] = document.get("dependencies")
        else:
            packages = [p for p in document["@graph"] if p.get("type") == "software_Package"]
            row["componentVersionsMatchCandidate"] = all(p.get("software_internalVersion") == pin for p in packages)
            row["declaredComponents"] = [{"name": p.get("name"), "version": p.get("software_internalVersion")} for p in packages]
            row["findings"] += [{"kind": "producer_nonstandard_properties", "name": p.get("name"), "properties": [key for key in ("externalUrl", "software_internalVersion") if key in p]} for p in packages]
        row["sdkRuntimeComponentsPresent"] = any(p.get("name") in {"Foundation", "Synchronization", "Swift", "MacOSX.sdk", "Xcode"} for p in packages)
        if not row["componentVersionsMatchCandidate"]:
            raise RuntimeError("SBOM candidate version mismatch")
        records.append(row)
result = {"scope": "Direct field/provenance audit only; not full semantic validation", "records": records,
          "disposition": "Retain unmodified producer output and report findings. Repository licence and toolchain/SDK evidence remain separate."}
(root / "field-audit.json").write_text(json.dumps(result, indent=2) + "\n")
print("Both SBOMs identify the exact candidate; producer field findings retained separately from schema validation.")
