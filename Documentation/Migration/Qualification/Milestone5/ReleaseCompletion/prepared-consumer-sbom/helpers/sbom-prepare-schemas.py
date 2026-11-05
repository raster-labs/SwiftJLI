#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Prepare isolated validator dependencies and retain versioned official schemas."""
import argparse
import datetime as dt
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--evidence", type=Path, required=True)
args = parser.parse_args()
root = args.evidence.resolve()
schemas = root / "schemas"
schemas.mkdir(parents=True, exist_ok=False)
scratch = Path(tempfile.mkdtemp(prefix="swiftjli-m5-sbom-validator-", dir="/private/tmp"))
report = {"startedUTC": dt.datetime.now(dt.timezone.utc).isoformat(), "scratch": str(scratch), "commands": [], "downloads": [], "status": "running"}

def save():
    (root / "schema-setup.json").write_text(json.dumps(report, indent=2) + "\n")

def run(label, command):
    log = root / (label + ".log")
    record = {"label": label, "command": command, "log": log.name}
    report["commands"].append(record)
    with log.open("w") as output:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=300)
    record["exitCode"] = result.returncode
    record["logSHA256"] = hashlib.sha256(log.read_bytes()).hexdigest()
    save()
    if result.returncode:
        raise RuntimeError(label + " failed")

try:
    run("validator-venv", [sys.executable, "-m", "venv", str(scratch / "venv")])
    python = str(scratch / "venv/bin/python")
    run("validator-install", [python, "-m", "pip", "install", "jsonschema==4.25.1"])
    run("validator-packages", [python, "-m", "pip", "freeze", "--all"])
    revision = "1ce97b2a7b8cf2429da248560d2aa671c6bce74a"
    urls = {"spdx-json-schema.json": "https://spdx.org/schema/3.0.1/spdx-json-schema.json"}
    urls.update({name: f"https://raw.githubusercontent.com/CycloneDX/specification/{revision}/schema/{name}" for name in ("bom-1.7.schema.json", "spdx.schema.json", "jsf-0.82.schema.json")})
    for name, url in urls.items():
        record = {"file": name, "url": url}
        report["downloads"].append(record)
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                data = response.read()
                record["resolvedURL"] = response.url
                record["httpStatus"] = response.status
            json.loads(data)
            zipped = gzip.compress(data, mtime=0)
            (schemas / (name + ".gz")).write_bytes(zipped)
            record.update(sha256=hashlib.sha256(data).hexdigest(), bytes=len(data), gzipSHA256=hashlib.sha256(zipped).hexdigest())
        except BaseException as error:
            record["error"] = repr(error)
            raise
        finally:
            save()
    report["validatorPython"] = python
    report["status"] = "passed"
except BaseException as error:
    report["status"] = "failed"
    report["failure"] = repr(error)
    raise
finally:
    report["finishedUTC"] = dt.datetime.now(dt.timezone.utc).isoformat()
    save()
print(python)
