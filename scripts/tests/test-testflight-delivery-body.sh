#!/usr/bin/env bash
# Render the actual report template without executing GitHub or upload commands.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
marker='<!-- delivery:test -->'
APP_NAME='Test app'
bundle='echo'
version='1.2'
build='3'
prs_text='#1'
sha='test-sha'
uploaded_at='2026-10-17T00:00:00Z'
availability='Uploaded'
run_url='https://github.com/example/repo/actions/runs/1'
template=$(sed -n '/^  body="\$marker/,/^  if /p' "$root/.github/scripts/record-testflight-delivery.sh" | sed '$d')
test -n "$template"
eval "$template"
[[ "$body" == *'(`echo`)'* ]]
[[ "$body" == *'Commit: `test-sha`'* ]]
[[ "$body" == *'Version/build: **1.2 (3)**'* ]]
echo 'TestFlight report template preserves literal Markdown backticks'
