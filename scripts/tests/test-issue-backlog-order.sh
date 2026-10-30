#!/usr/bin/env bash
# Regression contract for the repository-local issue admission order.
set -euo pipefail

script=.github/scripts/admit-one-stranded-issue.sh
grep -Fq -- '--limit 1000' "$script"
grep -Fq -- 'priority-high' "$script"
grep -Fq -- 'sort_by([if any(.labels[]?.name; . == "priority-high") then 0 elif any(.labels[]?.name; . == "qa-failed") then 1 else 2 end,' "$script"
grep -Fq -- 'A manual retry can be cancelled before it starts.' "$script"
grep -Fq -- 'select(.status == "completed" and .conclusion == "success")' "$script"
grep -Fq -- 'select(.status != "completed")' "$script"

order() {
  jq -r 'sort_by([if any(.labels[]?.name; . == "priority-high") then 0 else 1 end, .createdAt, .number])[] | .number'
}

actual=$(order <<'JSON'
[
  {"number": 30, "createdAt": "2026-01-03T00:00:00Z", "labels": []},
  {"number": 20, "createdAt": "2026-01-03T00:00:00Z", "labels": [{"name":"priority-high"}]},
  {"number": 10, "createdAt": "2026-01-01T00:00:00Z", "labels": []},
  {"number": 11, "createdAt": "2026-01-01T00:00:00Z", "labels": []}
]
JSON
)
expected=$'20\n10\n11\n30'
[[ "$actual" == "$expected" ]] || { echo "unexpected admission order: $actual" >&2; exit 1; }
echo 'issue backlog ordering policy: ok'

# A cancelled manual retry for an unchanged SHA must not erase the valid
# successful release record. Active runs remain an admission brake.
settled_successes() { jq '[.[] | select(.status == "completed" and .conclusion == "success")] | length'; }
active_releases() { jq '[.[] | select(.status != "completed")] | length'; }
fixture='[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"cancelled"}]'
[[ "$(settled_successes <<<"$fixture")" == 1 ]]
[[ "$(active_releases <<<"$fixture")" == 0 ]]
[[ "$(active_releases <<<'[{"status":"in_progress","conclusion":null}]')" == 1 ]]
echo 'release admission policy: cancelled retry preserves matching successful release'
