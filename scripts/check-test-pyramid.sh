#!/usr/bin/env bash
# Test-pyramid guardrail (test-pyramid plan, 2026-07-12, Phase 6).
#
# Keeps the pyramid from inverting again:
#   1. CadenceFeatures must never import SwiftUI/HealthKit/StoreKit/UIKit — that
#      is what keeps it buildable + testable on macOS under `swift test`.
#   2. Logic lives in CadenceFeatures, not in a View: no file under Features/
#      exceeds 400 LOC. A ratchet grandfathers the pre-existing large views whose
#      *logic* is already extracted (they now carry only SwiftUI markup); each may
#      only SHRINK from its recorded ceiling. Every other file is capped at 400.
#
# There is no XCUITest/simulator suite in this repo (removed: UI/simulator
# tests reliably crash CI and aren't run locally either). All behavioral
# coverage, including the Watch app, is headless `swift test`
# (CadenceCoreTests/CadenceFeaturesTests).
set -uo pipefail
shopt -s nullglob

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

FEATURES_SRC="$ROOT/CadenceCore/Sources/CadenceFeatures"
FEATURES_DIR="$ROOT/Cadence/Cadence/Features"
WATCH_SRC="$ROOT/Cadence/Cadence Watch App Watch App"

MAX_LOC=400

# ── 1. CadenceFeatures import ban ────────────────────────────────────────────
banned='^[[:space:]]*import[[:space:]]+(SwiftUI|HealthKit|StoreKit|UIKit|CoreBluetooth|CoreLocation)([[:space:]]|$)'
if grep -rEn "$banned" "$FEATURES_SRC" "$ROOT/CadenceCore/Sources/CadenceWorkoutFeatures" "$ROOT/CadenceCore/Sources/CadencePhoneFeatures" >/dev/null 2>&1; then
  echo "❌ CadenceFeatures imports a platform-UI framework — return a semantic enum instead:"
  grep -rEn "$banned" "$FEATURES_SRC" "$ROOT/CadenceCore/Sources/CadenceWorkoutFeatures" "$ROOT/CadenceCore/Sources/CadencePhoneFeatures"
  fail=1
fi

# ── 2. Views hold no logic (400-LOC budget, with a shrink-only ratchet) ──────
# Grandfathered files: "relative/path=current-ceiling". Lower these as you split;
# never raise them. Delete a line once the file drops under $MAX_LOC.
# Empty as of the DB++ migration (2026-08-24): every previously grandfathered view
# now fits the plain $MAX_LOC budget, so none of them may grow again.
ratchet() {
  case "$1" in
    *) echo "" ;;
  esac
}

while IFS= read -r f; do
  rel="${f#"$ROOT"/}"
  loc=$(wc -l < "$f" | tr -d ' ')
  ceiling="$(ratchet "$rel")"
  if [ -n "$ceiling" ]; then
    if [ "$loc" -gt "$ceiling" ]; then
      echo "❌ $rel grew to $loc LOC (ratchet ceiling $ceiling). Grandfathered views may only shrink."
      fail=1
    fi
  elif [ "$loc" -gt "$MAX_LOC" ]; then
    echo "❌ $rel is $loc LOC (max $MAX_LOC). Move logic to CadenceFeatures and split the view."
    fail=1
  fi
done < <(find "$FEATURES_DIR" -name '*.swift')

# ── 3. Watch view LOC cap ─────────────────────────────────────────────────────
if [ -d "$WATCH_SRC" ]; then
  while IFS= read -r f; do
    rel="${f#"$ROOT"/}"
    loc=$(wc -l < "$f" | tr -d ' ')
    if [ "$loc" -gt "$MAX_LOC" ]; then
      echo "❌ $rel is $loc LOC (max $MAX_LOC). Move logic to CadenceFeatures and split the view."
      fail=1
    fi
  done < <(find "$WATCH_SRC" -name '*.swift')
fi

if [ "$fail" -ne 0 ]; then
  echo "test-pyramid guardrail: FAILED"
  exit 1
fi
echo "test-pyramid guardrail: OK"
