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
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'Run logic tests\nTest LocalAudioRepairTests failed\nUpload artifact\n' >"$tmp/test-failure.log"
printf 'App Store Connect authentication failed\n' >"$tmp/deployment-failure.log"
[[ $(bash "$script" --classify-log "$tmp/test-failure.log") == code-test ]]
[[ $(bash "$script" --classify-log "$tmp/deployment-failure.log") == deployment ]]
echo 'Release repair policy: pre-publication validation; deployment failures escalate'
