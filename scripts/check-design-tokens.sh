#!/usr/bin/env bash
set -euo pipefail

# Ratchet only: this prevents raw semantic colors from growing while C2
# migrates screens to CadenceTheme/CadenceDataPalette.
baseline=338
count=$(rg -o '\.(green|blue|cyan|orange|red|teal|pink|yellow|purple|indigo|mint)\b' \
  Cadence/Cadence/Features --glob '*.swift' | wc -l | tr -d ' ')
if (( count > baseline )); then
  echo "design token guardrail failed: $count raw semantic colors (baseline $baseline)" >&2
  exit 1
fi
echo "design token guardrail: $count raw semantic colors (baseline $baseline)"
