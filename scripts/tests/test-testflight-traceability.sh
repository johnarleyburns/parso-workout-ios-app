#!/usr/bin/env bash
set -Eeuo pipefail
script=.github/scripts/record-testflight-delivery.sh
test -x "$script" || test -f "$script"
rg -q 'closingIssuesReferences' "$script"
rg -q 'testflight-delivery:' "$script"
rg -q 'CFBundleShortVersionString' "$script"
rg -q 'CFBundleVersion' "$script"
rg -q 'commits/\$commit/pulls' "$script"
rg -q 'issues/comments/\$existing' "$script"
rg -q 'claude-issue' "$script"
! rg -q 'declare -A|\$\{[^}]*,,\}|mapfile|readarray' "$script"
echo 'traceability static regression checks passed'
