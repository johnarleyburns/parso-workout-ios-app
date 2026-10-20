#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
for script in issue-to-pr.sh pr-conflict-repair.sh release-repair.sh; do
  file="$root/.github/scripts/$script"
  grep -Fq 'CLAUDE_MAX_TURNS="${CLAUDE_MAX_TURNS:-1000}"' "$file"
  grep -Fq 'CLAUDE_MAX_TURNS <= 1000' "$file"
  grep -Fq -- '--max-turns "$CLAUDE_MAX_TURNS"' "$file"
done
for workflow in issue-to-pr.yml pr-conflict-repair.yml release-repair.yml; do
  file="$root/.github/workflows/$workflow"
  grep -Fq "CLAUDE_MAX_TURNS: \${{ vars.CLAUDE_MAX_TURNS || '1000' }}" "$file"
  grep -Fq 'timeout-minutes: 360' "$file"
done
echo "Claude turn-budget configuration: passed"
