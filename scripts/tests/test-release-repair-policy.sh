#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/.github/scripts/release-repair.sh"
workflow="$root/.github/workflows/release-repair.yml"
grep -Eq 'workflow_run:' "$workflow"
grep -Eq 'conclusion == .failure.' "$workflow"
grep -Eq 'fix\\\(release\\\)' "$script"
grep -Eq 'This pull request does not close any issue' "$script"
grep -Eq 'provision|signing|certificate' "$script"
validate_line=$(grep -nF 'if validate "$attempt"' "$script" | cut -d: -f1)
commit_line=$(grep -nE '^git commit -m "fix\(release\)' "$script" | cut -d: -f1)
[[ "$validate_line" -lt "$commit_line" ]]
grep -Fq 'No branch or PR was published.' "$script"
echo 'Release repair policy: pre-publication validation; deployment failures escalate'
