#!/usr/bin/env python3
"""Check the frozen oracle corpus without importing or compiling Swift."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent
manifest = json.loads((root / "manifest.json").read_text())
assert manifest["schema"] == 1
assert manifest["fixtures"], "empty parity corpus"
expected = set()
for entry in manifest["fixtures"]:
    relative = Path(entry["path"])
    assert not relative.is_absolute() and ".." not in relative.parts
    data = (root / relative).read_bytes()
    assert len(data) == entry["bytes"], relative
    assert hashlib.sha256(data).hexdigest() == entry["sha256"], relative
    if relative.suffix == ".json":
        json.loads(data)
    elif relative.suffix == ".gama":
        assert data[:4] == b"GAMA" and int.from_bytes(data[4:6], "little") == 1, relative
    else:
        data.decode("utf-8")
    expected.add(relative.as_posix())
actual = {p.relative_to(root).as_posix() for p in (root / "swift-baseline").iterdir() if p.is_file()}
assert actual == expected, (actual - expected, expected - actual)
for phase in ("initial", "increment"):
    assert (root / f"swift-baseline/embed-{phase}.gama").read_bytes() == (root / f"swift-baseline/c-embed-{phase}.gama").read_bytes()
print(f"PASS: {len(expected)} frozen fixtures; hashes, JSON/UTF-8, GAMA v1 headers, 2 C/Swift byte matches")
