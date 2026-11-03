#!/usr/bin/env python3
"""Verify retained checkpoints and experiment hashes without builds or benchmarks."""
import hashlib
import json
from pathlib import Path
import runpy

root = Path(__file__).resolve().parent
runpy.run_path(str(root / "experiments" / "verify_archive.py"), run_name="__main__")
for name in ("checkpoint-f4a05be", "pipeline-14f3501"):
    directory = root / name
    manifest = json.loads((directory / "manifest.json").read_text())
    entries = manifest["files"] + manifest.get("generatedFiles", [])
    seen = set()
    for entry in entries:
        relative = Path(entry["path"])
        assert not relative.is_absolute() and ".." not in relative.parts, relative
        assert str(relative) not in seen, relative
        seen.add(str(relative))
        data = (directory / relative).read_bytes()
        assert len(data) == entry["bytes"], f"Size mismatch: {name}/{relative}"
        assert hashlib.sha256(data).hexdigest() == entry["sha256"], f"Hash mismatch: {name}/{relative}"
        text = data.decode("utf-8")
        assert "\0" not in text, f"Binary data: {name}/{relative}"
        if relative.suffix == ".json":
            json.loads(text)
    actual = {str(p.relative_to(directory)) for p in directory.rglob("*") if p.is_file()}
    assert actual == seen | {"manifest.json"}, f"Unlisted or missing file in {name}"
    print(f"Verified {name}: {len(manifest['files'])} original files, "
          f"{len(manifest.get('generatedFiles', []))} derived documents.")
