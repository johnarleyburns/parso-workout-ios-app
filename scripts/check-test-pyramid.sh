#!/usr/bin/env bash
# Test-pyramid guardrail (test-pyramid plan, 2026-07-12, Phase 6).
#
# Keeps the pyramid from inverting again:
#   1. CadenceFeatures must never import SwiftUI/HealthKit/StoreKit/UIKit — that
#      is what keeps it buildable + testable on macOS under `swift test`.
#   2. Normal XCUITest coverage is exactly ONE test function per UI device
#      target: one iPhone smoke test, one watch smoke test. The iPhone cap was
#      briefly 20 on 2026-08-18 and was reset to 1 the same day — coverage grows
#      by extending the single end-to-end flow (plan -> add exercise -> log a set
#      with partners -> complete), never by adding test functions, because each
#      one costs a full app launch in the pre-commit hook. Manual App Store
#      screenshot generation is allowed, but it must stay out of the default
#      Cadence test plan. New behavioral coverage still belongs in
#      CadenceFeaturesTests (headless `swift test`).
#   3. Logic lives in CadenceFeatures, not in a View: no file under Features/
#      exceeds 400 LOC. A ratchet grandfathers the pre-existing large views whose
#      *logic* is already extracted (they now carry only SwiftUI markup); each may
#      only SHRINK from its recorded ceiling. Every other file is capped at 400.
set -uo pipefail
shopt -s nullglob

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

FEATURES_SRC="$ROOT/CadenceCore/Sources/CadenceFeatures"
UITEST_DIR="$ROOT/Cadence/CadenceUITests"
IPHONE_SMOKE_FILE="$UITEST_DIR/SmokeLaunchTests.swift"
IPHONE_SCREENSHOT_FILE="$UITEST_DIR/AppStoreScreenshotsUITests.swift"
IPHONE_TEST_PLAN="$ROOT/Cadence/Cadence.xctestplan"
SCREENSHOT_TEST_PLAN="$ROOT/Cadence/Screenshots.xctestplan"
FEATURES_DIR="$ROOT/Cadence/Cadence/Features"
WATCH_SRC="$ROOT/Cadence/Cadence Watch App Watch App"
WATCH_UITEST_DIR="$ROOT/Cadence/Cadence Watch App Watch AppUITests"

MAX_LOC=400
EXPECTED_IPHONE_SMOKE_TESTS=1
EXPECTED_WATCH_SMOKE_TESTS=1

count_tests_in_files() {
  if [ "$#" -eq 0 ]; then echo 0; return; fi
  grep -rho "func test" "$@" 2>/dev/null | wc -l | tr -d ' '
}

# ── 1. CadenceFeatures import ban ────────────────────────────────────────────
banned='^[[:space:]]*import[[:space:]]+(SwiftUI|HealthKit|StoreKit|UIKit|CoreBluetooth|CoreLocation)([[:space:]]|$)'
if grep -rEn "$banned" "$FEATURES_SRC" >/dev/null 2>&1; then
  echo "❌ CadenceFeatures imports a platform-UI framework — return a semantic enum instead:"
  grep -rEn "$banned" "$FEATURES_SRC"
  fail=1
fi

# ── 2. iPhone UI suite is exactly one normal smoke test ─────────────────────
iphone_smoke_count=$(count_tests_in_files "$IPHONE_SMOKE_FILE")
if [ "${iphone_smoke_count:-0}" -ne "$EXPECTED_IPHONE_SMOKE_TESTS" ]; then
  echo "❌ iPhone smoke must have exactly $EXPECTED_IPHONE_SMOKE_TESTS test function in SmokeLaunchTests.swift (found $iphone_smoke_count)."
  echo "   Extend the single end-to-end flow instead of adding a test function, or"
  echo "   push new behavior coverage into CadenceFeaturesTests (swift test)."
  fail=1
fi

iphone_other_files=()
for f in "$UITEST_DIR"/*.swift; do
  case "$f" in
    "$IPHONE_SMOKE_FILE"|"$IPHONE_SCREENSHOT_FILE"|"$UITEST_DIR/UITestHelpers.swift") ;;
    *) iphone_other_files+=("$f") ;;
  esac
done
if [ "${#iphone_other_files[@]}" -eq 0 ]; then
  iphone_other_count=0
else
  iphone_other_count=$(count_tests_in_files "${iphone_other_files[@]}")
fi
if [ "${iphone_other_count:-0}" -ne 0 ]; then
  echo "❌ CadenceUITests has $iphone_other_count test function(s) outside SmokeLaunchTests.swift and the manual screenshot generator."
  echo "   Normal UI coverage is the one test in SmokeLaunchTests.swift; put other coverage in swift test."
  printf '   %s\n' "${iphone_other_files[@]#"$ROOT"/}"
  fail=1
fi

if ! grep -q '"AppStoreScreenshotsUITests"' "$IPHONE_TEST_PLAN" 2>/dev/null; then
  echo "❌ AppStoreScreenshotsUITests must stay skipped in Cadence.xctestplan."
  fail=1
fi
if ! grep -q '"AppStoreScreenshotsUITests' "$SCREENSHOT_TEST_PLAN" 2>/dev/null; then
  echo "❌ Screenshots.xctestplan must remain the manual runner for AppStoreScreenshotsUITests."
  fail=1
fi

# ── 3. Views hold no logic (400-LOC budget, with a shrink-only ratchet) ──────
# Grandfathered files: "relative/path=current-ceiling". Lower these as you split;
# never raise them. Delete a line once the file drops under $MAX_LOC.
ratchet() {
  case "$1" in
    "Cadence/Cadence/Features/Train/SessionView.swift") echo 1034 ;;
    "Cadence/Cadence/Features/Home/HomeView.swift") echo 1033 ;;
    "Cadence/Cadence/Features/Coach/CoachDecisionCardView.swift") echo 570 ;;
    "Cadence/Cadence/Features/Train/ExercisePickerView.swift") echo 514 ;;
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

# ── 4. Watch UI suite is one normal smoke test ──────────────────────────────
watch_ui_files=("$WATCH_UITEST_DIR"/*.swift)
watch_uitest_count=$(count_tests_in_files "${watch_ui_files[@]}")
if [ "${watch_uitest_count:-0}" -ne "$EXPECTED_WATCH_SMOKE_TESTS" ]; then
  echo "❌ Watch UITests must have exactly $EXPECTED_WATCH_SMOKE_TESTS smoke test function (found $watch_uitest_count)."
  echo "   Push new behavior coverage into CadenceFeaturesTests (swift test), not the simulator."
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
echo "test-pyramid guardrail: OK (iphone_smoke=$iphone_smoke_count, watch_smoke=$watch_uitest_count; screenshots manual-only)"
