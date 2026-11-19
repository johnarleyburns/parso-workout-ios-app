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
grep -Fq -- '--format json' "$script"
grep -Fq 'format_opencode_stream()' "$script"
grep -Fq 'jq -r --unbuffered' "$script"
grep -Fq '[step]' "$script"
grep -Fq '[tool]' "$script"
grep -Fq '[assistant]' "$script"
grep -Fq '[step] finished' "$script"
echo 'live stream formatting: tool calls and turns surface as readable lines'

# --- run_agent actually wires the formatter into the real call path, not
# just defines it unused. -----------------------------------------------
run_agent_body=$(sed -n '/^run_agent() {/,/^}/p' "$script")
grep -Fq 'format_opencode_stream' <<<"$run_agent_body"
grep -Fq -- 'tee -a "$stream_log"' <<<"$run_agent_body"
echo 'run_agent: json output is piped through the live formatter and persisted'

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
for phase in 'starting OpenCode implementation pass' 'candidate diff staged' 'validation attempt' 'PR #${pr_number} opened'; do
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

# --- In-process watchdog: the heartbeat kills a genuinely stalled `opencode`
# itself (tracking real stream-log growth, not just "is the heartbeat
# subshell alive" - which is always true) instead of only reporting on it.
# 2026-11-10, issue #619: a run sat with its event counter frozen at 83 for
# 4+ hours because nothing compared progress across ticks. -----------------
grep -Fq 'agent_pid_file=' "$script"
grep -Fq 'stall_limit_minutes=' "$script"
grep -Eq 'last_count|last_change_epoch' "$script"
grep -Fq 'pkill -9 -P "$pid"' "$script"
grep -Fq 'kill -9 "$pid"' "$script"
grep -Fq 'last new output' "$script"
echo 'in-process watchdog: a stalled opencode process is killed, not just narrated'

# --- run_agent backgrounds opencode itself (not tee/format_opencode_stream) so
# $agent_pid_file names the process the watchdog actually needs to kill. --
grep -Fq 'echo "$pid" > "$agent_pid_file"' <<<"$run_agent_body"
grep -Eq '> >\(tee -a "\$stream_log" \| format_opencode_stream\) &' <<<"$run_agent_body"
echo 'run_agent: backgrounds opencode directly so its own pid is recorded'

# --- The controller's stall warning reads the watchdog's own "last new
# output Nm ago" number instead of the heartbeat comment's timestamp (which
# the heartbeat rewrites every 5 minutes regardless of real progress, so it
# can never go stale - the exact reason issue #619 went undetected). -------
grep -Fq "last new output [0-9]+m ago" "$controller"
! grep -Fq 'updated_at' "$controller"
echo 'controller stall detection: reads real progress, not comment recency'
