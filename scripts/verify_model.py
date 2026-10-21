#!/usr/bin/env python3
"""Verify the bundled FP16 model using Python's standard library."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "Models"
manifest = json.loads((root / "SHA256.json").read_text())
actual = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()}
expected = set(manifest) | {"SHA256.json"}
if actual != expected:
    raise SystemExit(f"Model file set changed: {sorted(actual ^ expected)}")
for name, expected in manifest.items():
    path = root / name
    if path.stat().st_size != expected["bytes"]:
        raise SystemExit(f"Size mismatch: {name}")
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected["sha256"]:
        raise SystemExit(f"SHA256 mismatch: {name}")
print(f"PASS: {len(manifest)} model files match SHA256.json")
