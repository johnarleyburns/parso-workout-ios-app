#!/usr/bin/env bash
# Watch background-mode guardrail.
#
# watchOS keeps a workout app running with the screen off only when its
# Info.plist lists `workout-processing` under WKBackgroundModes. On 2026-08-28
# the value was removed from UIBackgroundModes (where App Store Connect rejects
# it) without being added to WKBackgroundModes, so the Watch was suspended at
# every wrist-down and live heart rate stopped reaching the phone until the
# screen woke. This fails if the mode goes missing again, or lands under the
# wrong key.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLISTS=(
  "$ROOT/Cadence/Cadence-Watch-App-Watch-App-Info.plist"
  "$ROOT/Cadence/Cadence Watch App Watch App/Cadence-Watch-App-Watch-App-Info.plist"
)

# Prints the <string> values of the array that follows <key>$1</key>.
array_values() {
  awk -v key="<key>$1</key>" '
    index($0, key) { found = 1; next }
    found && /<array\/>/ { exit }
    found && /<\/array>/ { exit }
    found && /<string>/ {
      line = $0
      sub(/.*<string>/, "", line); sub(/<\/string>.*/, "", line)
      print line
    }
  ' "$2"
}

fail=0
for plist in "${PLISTS[@]}"; do
  rel="${plist#"$ROOT"/}"
  if [ ! -f "$plist" ]; then
    echo "❌ missing $rel"
    fail=1
    continue
  fi
  if ! array_values WKBackgroundModes "$plist" | grep -qx "workout-processing"; then
    echo "❌ $rel: WKBackgroundModes must include workout-processing"
    fail=1
  fi
  if array_values UIBackgroundModes "$plist" | grep -qx "workout-processing"; then
    echo "❌ $rel: workout-processing belongs in WKBackgroundModes, not UIBackgroundModes"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "watch-background-modes guardrail: FAILED"
  exit 1
fi
echo "watch-background-modes guardrail: OK"
