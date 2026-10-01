#!/usr/bin/env bash
# Localization guardrail. Every String Catalog key must have a non-empty value
# in every shipped locale (Xcode silently falls back to English otherwise),
# keys whose English varies by plural must vary by plural in every locale, no
# key may be stale, and hand-built English plurals (`n == 1 ? "" : "s"`) may not
# come back. The DB++ exercise-name sidecar must cover every locale too.
# Keys come from the compiler: run scripts/sync-localization-catalogs.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import json, pathlib, re, sys

locales = ["en-GB", "de", "es", "fr", "nl", "pt-BR", "zh-Hans", "zh-Hant"]
catalogs = [
    "Cadence/Cadence/Localizable.xcstrings",
    "Cadence/Cadence/AppShortcuts.xcstrings",
    "Cadence/Cadence/InfoPlist.xcstrings",
    "Cadence/Cadence Watch App Watch App/Localizable.xcstrings",
    "Cadence/Cadence Watch App Watch App/InfoPlist.xcstrings",
    "CadenceWidgets/Localizable.xcstrings",
    "CadenceWidgets/InfoPlist.xcstrings",
    "CadenceWatchWidgets/Localizable.xcstrings",
    "CadenceCore/Sources/CadenceCore/Resources/Localizable.xcstrings",
    "CadenceCore/Sources/CadenceFeatures/Resources/Localizable.xcstrings",
]
errors = []

def units(loc):
    if not loc:
        return []
    if "stringUnit" in loc:
        return [loc["stringUnit"]]
    if "stringSet" in loc:
        s = loc["stringSet"]
        return [{"state": s.get("state"), "value": v} for v in s.get("values", [])]
    plural = loc.get("variations", {}).get("plural", {})
    return [v.get("stringUnit", {}) for v in plural.values()]

def is_plural(loc):
    return bool(loc and loc.get("variations", {}).get("plural"))

total = 0
for path in catalogs:
    p = pathlib.Path(path)
    if not p.is_file():
        errors.append(f"missing catalog: {path}")
        continue
    data = json.loads(p.read_text())
    for key, entry in data.get("strings", {}).items():
        if entry.get("extractionState") == "stale":
            errors.append(f"{path}: stale key {key!r}")
            continue
        if entry.get("shouldTranslate") is False:
            continue
        total += 1
        locs = entry.get("localizations", {})
        english_plural = is_plural(locs.get("en"))
        for locale in locales:
            us = units(locs.get(locale))
            if not us or any(not (u.get("value") or "").strip() for u in us):
                errors.append(f"{path}: {key!r} missing {locale}")
            elif any(u.get("state") not in ("translated", "needs_review") for u in us):
                errors.append(f"{path}: {key!r} has an unexpected {locale} state")
            elif english_plural and not is_plural(locs.get(locale)):
                errors.append(f"{path}: {key!r} varies by plural in English but not in {locale}")

sidecar = json.loads(pathlib.Path("CadenceCore/Sources/CadenceCore/Resources/exercise-names.i18n.json").read_text())
for name, values in sidecar.items():
    missing = [l for l in ["en"] + locales if l not in values]
    if missing:
        errors.append(f"exercise-names sidecar: {name!r} missing {', '.join(missing)}")

hand_plurals = []
for root in ("Cadence/Cadence", "Cadence/Cadence Watch App Watch App", "CadenceWidgets",
             "CadenceWatchWidgets", "CadenceCore/Sources"):
    for path in pathlib.Path(root).rglob("*.swift"):
        for n, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
            if re.search(r'==\s*1\s*\?\s*"', line):
                hand_plurals.append(f"{path}:{n}")
for hit in hand_plurals:
    errors.append(f"hand-built English plural (use a catalog plural instead): {hit}")

if errors:
    print("localization guardrail failed:")
    print("\n".join(f"  - {e}" for e in errors[:200]))
    if len(errors) > 200:
        print(f"  … and {len(errors) - 200} more")
    sys.exit(1)
print(f"localization guardrail: {len(catalogs)} catalogs, {total} keys, {len(locales) + 1} locales, {len(sidecar)} DB++ names")
PY
