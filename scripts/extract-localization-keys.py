#!/usr/bin/env python3
"""Report SwiftUI string literals that should be reviewed by localization."""
import pathlib, re
root = pathlib.Path(__file__).resolve().parents[1]
patterns = re.compile(r'(?:Text|Label|Button|navigationTitle)\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"')
keys = set()
for path in (root / "Cadence/Cadence").rglob("*.swift"):
    keys.update(patterns.findall(path.read_text(errors="ignore")))
for key in sorted(keys, key=str.casefold):
    print(key)
print(f"\n{len(keys)} source literals", file=__import__("sys").stderr)
