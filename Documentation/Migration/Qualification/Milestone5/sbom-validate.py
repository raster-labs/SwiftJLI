#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independently validate unmodified generated SBOMs against pinned schemas."""
import argparse
import gzip
import hashlib
import importlib.metadata
import json
from pathlib import Path
import sys
from urllib.parse import urlparse
from jsonschema.validators import validator_for
from referencing import Registry, Resource

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--evidence", type=Path, required=True)
args = parser.parse_args()
root = args.evidence.resolve()
schemas = root / "schemas"
names = {"spdx-json-schema.json", "bom-1.7.schema.json", "spdx.schema.json", "jsf-0.82.schema.json"}

def raw_schema(name):
    return gzip.decompress((schemas / (name + ".gz")).read_bytes())

def retrieve(uri):
    name = urlparse(uri).path.rsplit("/", 1)[-1]
    if name not in names:
        raise ValueError("Unrecorded schema reference: " + uri)
    return Resource.from_contents(json.loads(raw_schema(name)))

registry = Registry(retrieve=retrieve)
records = []
for spec, name in (("spdx", "spdx-json-schema.json"), ("cyclonedx", "bom-1.7.schema.json")):
    schema = json.loads(raw_schema(name))
    cls = validator_for(schema)
    cls.check_schema(schema)
    files = sorted((root / spec).glob("*.json"))
    if not files:
        raise RuntimeError("No " + spec + " SBOM to validate")
    for path in files:
        document = json.loads(path.read_bytes())
        errors = sorted(cls(schema, registry=registry, format_checker=cls.FORMAT_CHECKER).iter_errors(document), key=lambda e: str(list(e.path)))
        records.append({"file": str(path.relative_to(root)), "schema": name,
            "fileSHA256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "schemaSHA256": hashlib.sha256(raw_schema(name)).hexdigest(),
            "validator": "jsonschema " + importlib.metadata.version("jsonschema"),
            "referencing": importlib.metadata.version("referencing"),
            "status": "passed" if not errors else "failed",
            "errors": [{"path": list(e.path), "schemaPath": list(e.schema_path), "message": e.message} for e in errors]})
        print(spec, records[-1]["status"], len(errors), "schema findings")
result = {"scope": "JSON Schema validation of unmodified build-associated outputs; not complete SBOM semantic or SDK/runtime inventory validation",
          "records": records, "status": "passed" if all(r["status"] == "passed" for r in records) else "failed"}
(root / "schema-results.json").write_text(json.dumps(result, indent=2) + "\n")
sys.exit(0 if result["status"] == "passed" else 1)
