#!/usr/bin/env python3
"""Verify this text archive without reading or rebuilding the original workspace."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
manifest = json.loads((root / "SOURCE_MANIFEST.json").read_text())
entries = manifest["files"] + manifest.get("generatedFiles", [])
seen = set()
for entry in entries:
    relative = Path(entry["archivedPath"])
    assert not relative.is_absolute() and ".." not in relative.parts, relative
    assert str(relative) not in seen, relative
    seen.add(str(relative))
    data = (root / relative).read_bytes()
    assert len(data) == entry["bytes"], f"Size mismatch: {relative}"
    assert hashlib.sha256(data).hexdigest() == entry["sha256"], f"Hash mismatch: {relative}"
    text = data.decode("utf-8")
    assert "\0" not in text, f"Binary data: {relative}"
    if relative.suffix == ".json":
        json.loads(text)
    elif relative.suffix == ".jsonl":
        for line in text.splitlines():
            if line.strip():
                json.loads(line)
assert len(manifest["files"]) == manifest["copiedFileCount"]
assert sum(item["bytes"] for item in manifest["files"]) == manifest["copiedBytes"]
actual = {str(path.relative_to(root)) for path in root.rglob("*") if path.is_file()}
assert actual == seen | {"SOURCE_MANIFEST.json"}, "Unlisted or missing archive file"
print(f"Verified {len(manifest['files'])} original files and {len(entries) - len(manifest['files'])} archive documents.")
