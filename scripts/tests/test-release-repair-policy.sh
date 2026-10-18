#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/.github/scripts/release-repair.sh"
workflow="$root/.github/workflows/release-repair.yml"
rg -q 'workflow_run:' "$workflow"
rg -q 'conclusion == .failure.' "$workflow"
rg -q 'fix\\\(release\\\)' "$script"
rg -q 'This pull request does not close any issue' "$script"
rg -q 'provision|signing|certificate' "$script"
echo 'Release repair policy: bounded code repair; deployment failures escalate'
