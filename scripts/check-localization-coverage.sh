#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$ROOT/Cadence/Cadence/Localizable.xcstrings"
SIDECAR="$ROOT/CadenceCore/Sources/CadenceCore/Resources/exercise-names.i18n.json"

python3 - "$CATALOG" "$SIDECAR" <<'PY'
import json, pathlib, re, sys
catalog = json.load(open(sys.argv[1]))
sidecar = json.load(open(sys.argv[2]))
locales = ["en", "en-GB", "de", "es", "fr", "nl", "pt-BR", "zh-Hans", "zh-Hant"]
missing = []
for key, value in catalog.get("strings", {}).items():
    present = set((value.get("localizations") or {}).keys())
    if key in {"Start Workout", "Log Set", "Suggested for you", "This week", "Fill the gaps", "New personal record"}:
        missing.extend(f"{key}: {locale}" for locale in locales if locale not in present)
if missing:
    raise SystemExit("localization guardrail failed:\n" + "\n".join(missing))
if len(sidecar) < 10 or any(not set(locales).issubset(value) for value in sidecar.values()):
    raise SystemExit("localization guardrail failed: DB++ exercise sidecar is incomplete")
source_files = list(pathlib.Path(sys.argv[1]).parents[2].glob("**/*.swift"))
literals = set()
for path in source_files:
    text = path.read_text(errors="ignore")
    literals.update(re.findall(r'(?:Text|Label|Button|navigationTitle)\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"', text))
print(f"localization guardrail: {len(catalog.get('strings', {}))} catalog keys, {len(literals)} source literals scanned, {len(sidecar)} DB++ names with {len(locales)} locale slots")
PY
