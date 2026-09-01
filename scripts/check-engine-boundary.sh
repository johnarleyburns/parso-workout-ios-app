#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

allowed="CadenceCore/Sources/CadenceCore/TrainingEngineBridge.swift"
imports="$(rg -l \
  --glob '*.swift' \
  --glob '!**/.build/**' \
  --glob '!**/DerivedData/**' \
  --glob '!**/.git/**' \
  '^[[:space:]]*import[[:space:]]+FreeExerciseDBPlusPlus[[:space:]]*$' \
  . || true)"

while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    file="${file#./}"
    if [[ "$file" != "$allowed" ]]; then
        echo "engine-boundary guardrail: forbidden import in $file" >&2
        exit 1
    fi
done <<< "$imports"

if ! grep -Eq '^[[:space:]]*import[[:space:]]+FreeExerciseDBPlusPlus[[:space:]]*$' "$allowed"; then
    echo "engine-boundary guardrail: allowed boundary file has no DB++ import" >&2
    exit 1
fi

echo "engine-boundary guardrail: OK"
