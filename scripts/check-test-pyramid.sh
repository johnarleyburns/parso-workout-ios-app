#!/usr/bin/env bash
# Test-pyramid guardrail (test-pyramid plan, 2026-07-12, Phase 6).
#
# Keeps the pyramid from inverting again:
#   1. CadenceFeatures must never import SwiftUI/HealthKit/StoreKit/UIKit — that
#      is what keeps it buildable + testable on macOS under `swift test`.
#   2. The XCUITest suite is a fixed smoke gate and does not grow — new coverage
#      goes into CadenceFeaturesTests (headless `swift test`), not the simulator.
#   3. Logic lives in CadenceFeatures, not in a View: no file under Features/
#      exceeds 400 LOC. A ratchet grandfathers the pre-existing large views whose
#      *logic* is already extracted (they now carry only SwiftUI markup); each may
#      only SHRINK from its recorded ceiling. Every other file is capped at 400.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

FEATURES_SRC="$ROOT/CadenceCore/Sources/CadenceFeatures"
UITEST_DIR="$ROOT/Cadence/CadenceUITests"
FEATURES_DIR="$ROOT/Cadence/Cadence/Features"
WATCH_SRC="$ROOT/Cadence/Cadence Watch App Watch App"
WATCH_UITEST_DIR="$ROOT/Cadence/Cadence Watch App Watch AppUITests"

MAX_LOC=400
MAX_UITESTS=12
MAX_WATCH_UITESTS=3

# ── 1. CadenceFeatures import ban ────────────────────────────────────────────
banned='^[[:space:]]*import[[:space:]]+(SwiftUI|HealthKit|StoreKit|UIKit|CoreBluetooth|CoreLocation)([[:space:]]|$)'
if grep -rEn "$banned" "$FEATURES_SRC" >/dev/null 2>&1; then
  echo "❌ CadenceFeatures imports a platform-UI framework — return a semantic enum instead:"
  grep -rEn "$banned" "$FEATURES_SRC"
  fail=1
fi

# ── 2. Smoke suite does not grow ─────────────────────────────────────────────
uitest_count=$(grep -rho "func test" "$UITEST_DIR"/*.swift 2>/dev/null | wc -l | tr -d ' ')
if [ "${uitest_count:-0}" -gt "$MAX_UITESTS" ]; then
  echo "❌ CadenceUITests has $uitest_count test functions (max $MAX_UITESTS)."
  echo "   Push new coverage into CadenceFeaturesTests (swift test), not the simulator."
  fail=1
fi

# ── 3. Views hold no logic (400-LOC budget, with a shrink-only ratchet) ──────
# Grandfathered files: "relative/path=current-ceiling". Lower these as you split;
# never raise them. Delete a line once the file drops under $MAX_LOC.
ratchet() {
  case "$1" in
    "Cadence/Cadence/Features/Train/SessionView.swift") echo 1102 ;;
    "Cadence/Cadence/Features/Home/HomeView.swift") echo 1115 ;;
    "Cadence/Cadence/Features/Coach/CoachDecisionCardView.swift") echo 570 ;;
    "Cadence/Cadence/Features/Train/ExercisePickerView.swift") echo 532 ;;
    "Cadence/Cadence/Features/Plan/RecordAssessmentView.swift") echo 439 ;;
    "Cadence/Cadence/Features/Coach/YourWeekView.swift") echo 406 ;;
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
    else
      echo "⚠️  $rel is $loc LOC (grandfathered ≤$ceiling; split it down toward $MAX_LOC)."
    fi
  elif [ "$loc" -gt "$MAX_LOC" ]; then
    echo "❌ $rel is $loc LOC (max $MAX_LOC). Move logic to CadenceFeatures and split the view."
    fail=1
  fi
done < <(find "$FEATURES_DIR" -name '*.swift')

# ── 4. Watch UI smoke cap (≤3 tests) ─────────────────────────────────────────
watch_uitest_count=$(grep -rho "func test" "$WATCH_UITEST_DIR"/*.swift 2>/dev/null | wc -l | tr -d ' ')
if [ "${watch_uitest_count:-0}" -gt "$MAX_WATCH_UITESTS" ]; then
  echo "❌ Watch UITests has $watch_uitest_count test functions (max $MAX_WATCH_UITESTS)."
  echo "   Push new coverage into CadenceFeaturesTests (swift test), not the simulator."
  fail=1
fi

# ── 5. Watch view LOC cap ─────────────────────────────────────────────────────
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
echo "test-pyramid guardrail: OK (uitests=$uitest_count/$MAX_UITESTS, watch_uitests=$watch_uitest_count/$MAX_WATCH_UITESTS)"
