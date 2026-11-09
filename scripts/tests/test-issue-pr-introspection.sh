#!/usr/bin/env bash
# Regression contract for the issue-to-pr worker's progress introspection:
# live tool-call streaming, an independent heartbeat, step-summary
# checkpoints, and the controller's stall detector. Before this, the
# "Implement and open draft PR" step produced zero output until it finished
# or hit the 360-minute job timeout, so a stuck run and a busy run looked
# identical.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/.github/scripts/issue-to-pr.sh"
controller="$root/.github/scripts/admit-one-stranded-issue.sh"

# --- Live stream formatting: each tool call/turn becomes one readable line
# as it happens, instead of nothing until the whole run finishes. The worker
# owns the dynamic Ubuntu execution; this portable guardrail checks its source
# contract without depending on the host shell/jq combination. -------------
grep -Fq -- '--output-format stream-json' "$script"
grep -Fq -- '--verbose' "$script"
grep -Fq 'format_claude_stream()' "$script"
grep -Fq 'jq -r --unbuffered' "$script"
grep -Fq '[system]' "$script"
grep -Fq '[tool]' "$script"
grep -Fq '[assistant]' "$script"
grep -Fq '[done] turns=' "$script"
echo 'live stream formatting: tool calls and turns surface as readable lines'

# --- run_claude actually wires the formatter into the real call path, not
# just defines it unused. -----------------------------------------------
run_claude_body=$(sed -n '/^run_claude() {/,/^}/p' "$script")
grep -Fq 'format_claude_stream' <<<"$run_claude_body"
grep -Fq -- 'tee -a "$stream_log"' <<<"$run_claude_body"
echo 'run_claude: stream-json output is piped through the live formatter and persisted'

# --- Heartbeat: an independent liveness signal plus a single pinned issue
# comment, not spammed per-minute. ---------------------------------------
grep -Fq 'start_heartbeat()' "$script"
grep -Fq 'stop_heartbeat()' "$script"
grep -Fq 'trap stop_heartbeat EXIT' "$script"
grep -Fq 'claude-progress-heartbeat' "$script"
grep -Fq 'start_heartbeat' "$script"
heartbeat_calls=$(grep -c '^start_heartbeat$' "$script")
[[ "$heartbeat_calls" -eq 1 ]]
echo 'heartbeat: independent liveness signal and single pinned issue comment wired in'

# --- Step-summary checkpoints: phase progress visible on the run page
# itself (renders incrementally), not only in the eventual logs. ---------
grep -Fq 'GITHUB_STEP_SUMMARY' "$script"
for phase in 'starting Claude implementation pass' 'candidate diff staged' 'validation attempt' 'PR #${pr_number} opened'; do
  grep -Fq "$phase" "$script"
done
echo 'step-summary checkpoints: phase progress recorded for the run page'

# --- Controller stall detection: a reservation holder with a stale
# heartbeat gets flagged instead of looking identical to a busy one. -----
grep -Fq 'check_stall_and_warn()' "$controller"
grep -Fq 'claude-progress-heartbeat' "$controller"
grep -Fq 'possibly-stuck' "$controller"
grep -Fq 'check_stall_and_warn "$active"' "$controller"
echo 'controller stall detection: a silent reservation holder is flagged, not just waited on'
