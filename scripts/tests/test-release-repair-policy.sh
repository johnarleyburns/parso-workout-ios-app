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
echo 'Release repair policy: bounded code repair; deployment failures escalate'
