#!/usr/bin/env bash
set -euo pipefail

# C5 accessibility ratchet. Deliberately counts only literal widths/heights in
# shipped feature views; 44pt controls and fixed chart/icon geometry are still
# valid, but new layout constraints must not accumulate.
root="$(cd "$(dirname "$0")/.." && pwd)"
features="$root/Cadence/Cadence/Features"
max_fixed_width=68
max_single_line=26

fixed_width=$(rg -n 'frame\(width:[[:space:]]*[0-9]+' "$features" --glob '*.swift' | wc -l | tr -d ' ')
single_line=$(rg -n 'lineLimit\(1\)' "$features" --glob '*.swift' | wc -l | tr -d ' ')

if (( fixed_width > max_fixed_width )); then
  echo "accessibility ratchet failed: $fixed_width literal frame widths (baseline $max_fixed_width)" >&2
  exit 1
fi
if (( single_line > max_single_line )); then
  echo "accessibility ratchet failed: $single_line lineLimit(1) uses (baseline $max_single_line)" >&2
  exit 1
fi
echo "accessibility ratchet: fixed_width=$fixed_width/$max_fixed_width lineLimit1=$single_line/$max_single_line"

# Live workout roots must reflow (wrap / scroll / vertical layouts) instead of
# shrinking text: no minimumScaleFactor below 1. ShareCardRenderer is a fixed
# exported image and is intentionally excluded.
live_roots=("$features/Train" "$features/Intervals" "$features/Shared/WorkoutElapsedHeader.swift"
  "$features/Coach/CoachDecisionCardView.swift" "$features/Coach/CoachRow.swift"
  "$features/Home/HomeTodayHeroCard.swift" "$features/Home/MuscleFocusThumbnail.swift"
  "$features/Progress/ProgressStrengthChartView.swift" "$root/Cadence/Cadence/App/RootTabView.swift")
if rg -n 'minimumScaleFactor\((0?\.[0-9]+|0)\)' "${live_roots[@]}" --glob '*.swift'; then
  echo "accessibility ratchet failed: sub-1 minimumScaleFactor in a live workout root" >&2
  exit 1
fi

# Live Watch workout surfaces (weight entry, keypad, interval, strength card)
# must reflow/scroll too, never shrink text to fit.
watch="$root/Cadence/Cadence Watch App Watch App"
# Audited: every Watch source file (issue #305); no exclusions without a test-reviewed rationale.
watch_live=("$watch")
if rg -n 'minimumScaleFactor\((0?\.[0-9]+|0)\)' "${watch_live[@]}" --glob '*.swift'; then
  echo "accessibility ratchet failed: sub-1 minimumScaleFactor in a live Watch workout view" >&2
  exit 1
fi
