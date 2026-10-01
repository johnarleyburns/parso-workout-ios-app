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
