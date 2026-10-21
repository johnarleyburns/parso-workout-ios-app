#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/.github/scripts/reconcile-testflight-status.sh"
fixture=$(mktemp)
trap 'rm -f "$fixture"' EXIT
cat > "$fixture" <<'EOF'
ordinary issue comment
<!-- testflight-delivery:guru.parso.example:1.2.3:456 -->
newer comment
<!-- testflight-delivery:guru.parso.example:1.2.4:457 -->
EOF

marker=$(grep -hE '<!-- testflight-delivery:[^:]+:[^:]+:[^ ]+ -->' "$fixture" | tail -n 1)
[[ "$marker" == '<!-- testflight-delivery:guru.parso.example:1.2.4:457 -->' ]]
grep -Fq 'delivery=$(grep -hE' "$script"
! grep -Fq 'delivery=$(rg ' "$script"
grep -Fq 'gh issue list --repo "$repo" --state open --limit 1000' "$script"
echo "TestFlight reconciler discovery: passed"
