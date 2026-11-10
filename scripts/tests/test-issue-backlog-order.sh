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
grep -Fq -- 'terminal_failed_release' "$script"
grep -Fq -- 'generated_pr_blocks_admission()' "$script"
grep -Fq -- 'terminal non-success validation' "$script"

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
terminal_failed_releases() { jq '[.[] | select(.status == "completed" and .conclusion != "success")] | length'; }
fixture='[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"cancelled"}]'
[[ "$(settled_successes <<<"$fixture")" == 1 ]]
[[ "$(active_releases <<<"$fixture")" == 0 ]]
[[ "$(active_releases <<<'[{"status":"in_progress","conclusion":null}]')" == 1 ]]
echo 'release admission policy: cancelled retry preserves matching successful release'

# A failed TestFlight release belongs to release repair, just as a failed PR
# validation belongs to PR maintenance. It cannot hold unrelated issue PRs.
# A release that is still running, or a SHA with no completed release at all,
# remains an admission brake.
release_blocks_admission() {
  local active successful terminal_failed
  active=$(active_releases <<<"$1")
  successful=$(settled_successes <<<"$1")
  terminal_failed=$(terminal_failed_releases <<<"$1")
  if (( active > 0 )); then return 0; fi
  if (( successful == 0 && terminal_failed == 0 )); then return 0; fi
  return 1
}
blocks_release() { release_blocks_admission "$1" && echo yes || echo no; }
[[ "$(blocks_release '[{"status":"in_progress","conclusion":null}]')" == yes ]]
[[ "$(blocks_release '[]')" == yes ]]
[[ "$(blocks_release '[{"status":"completed","conclusion":"failure"}]')" == no ]]
[[ "$(blocks_release '[{"status":"completed","conclusion":"cancelled"}]')" == no ]]
[[ "$(blocks_release '[{"status":"completed","conclusion":"success"}]')" == no ]]
echo 'failed release admission policy: terminal failed releases do not hold the queue'

# A failed/cancelled PR is handed to PR maintenance; it is not a permanent
# repository-wide admission lock. Pending, missing, and passing PR checks still
# serialize work so a new implementation always starts from settled main.
generated_pr_blocks_admission() {
  jq -e '
    (.workflow_runs // []) as $runs
    | if ($runs | length) == 0 then true
      elif any($runs[]; .status != "completed") then true
      elif any($runs[]; .conclusion == "success") then true
      else false
      end' >/dev/null
}
blocks() { generated_pr_blocks_admission <<<"$1" && echo yes || echo no; }
[[ "$(blocks '{"workflow_runs":[]}')" == yes ]]
[[ "$(blocks '{"workflow_runs":[{"status":"in_progress","conclusion":null}]}')" == yes ]]
[[ "$(blocks '{"workflow_runs":[{"status":"completed","conclusion":"success"}]}')" == yes ]]
[[ "$(blocks '{"workflow_runs":[{"status":"completed","conclusion":"failure"}]}')" == no ]]
[[ "$(blocks '{"workflow_runs":[{"status":"completed","conclusion":"cancelled"}]}')" == no ]]
echo 'failed PR admission policy: terminal failed PRs do not hold the queue'
