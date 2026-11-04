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
# A closed issue may still be waiting for Apple processing.  It must remain in
# the reconciliation set so its availability comment/labels become accurate.
grep -Fq 'gh issue list --repo "$repo" --state all --limit 1000 --json number,labels' "$script"
grep -Fq 'startswith("testflight-")' "$script"

# Apple VALID is the delivery boundary.  The issue closes only after the
# reconciler has recorded availability, and the human `qa-failed` repair path
# remains explicit in the auto-close comment.
grep -Fq 'if [[ "$status" == Apple\ processing\ completed* ]]; then' "$script"
grep -Fq 'gh issue close "$issue" --repo "$repo" --reason completed' "$script"
grep -Fq 'add \`qa-failed\` to reopen this issue for repair' "$script"
echo "TestFlight reconciler discovery and auto-close policy: passed"
