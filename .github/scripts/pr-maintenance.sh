#!/usr/bin/env bash
# PR lifecycle reconciler: the single owner of "what happens next" for open
# Claude PRs. It never runs Claude and never executes PR-controlled code; it
# only reads GitHub state and performs narrow API actions:
#   mark ready, enable auto-merge, update-branch (GitHub-side non-force merge of
#   main), re-trigger/re-run validation, dispatch the repair workflow, escalate.
#
# Lifecycle (decide() is the only place that maps state -> action):
#   stopped            -> nothing (human-review stop recorded for this head)
#   dirty|failed       -> repair (bounded by 3 attempts, persisted) / exhausted
#   action_required    -> escalate (GitHub approval policy; never "passed")
#   cancelled          -> rerun       missing -> retrigger (close/reopen)
#   pending            -> wait
#   success + behind   -> update-branch (strict required checks demand freshness)
#   success otherwise  -> advance (ready + auto-merge) / waiting-merge
#
# Env: GH_TOKEN (PAT or app token so pushes start workflows), GITHUB_REPOSITORY,
#      optional TARGET_PR, DRY_RUN=1.
# Exit: 0 = reconciled (including waits/escalations, which are durable state);
#       1 = infrastructure failure (GitHub API errors) so the run is red.
set -uo pipefail

owner='johnarleyburns'
label='needs-human-review'
max_attempts=3
repo="${GITHUB_REPOSITORY:-}"
run_url="${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${GITHUB_RUN_ID:-0}"
REPORT="${REPORT_FILE:-/tmp/pr-maintenance-report.json}"
INFRA=0
ACTIONS_STARTED=0
FIX_VERSION=130   # bump to re-migrate stops caused by a newly fixed automation defect

# decide <draft> <state> <validation> <automerge> <stopped> <attempts> [approval_tries]
decide() {
  local draft="$1" state="$2" val="$3" autom="$4" stopped="$5" attempts="$6" atries="${7:-0}"
  [[ "$stopped" == true ]] && { echo stopped; return; }
  [[ "$val" == pending ]] && { echo wait; return; }
  # Refresh outdated infrastructure once before retrying a stale failed head.
  if [[ "$state" == behind && "$val" != action_required ]]; then
    echo update-branch; return
  fi
  if [[ "$state" == dirty || "$val" == failed ]]; then
    (( attempts >= max_attempts )) && echo exhausted || echo repair
    return
  fi
  case "$val" in
    action_required) (( atries < 1 )) && echo resync-approval || echo escalate-approval; return ;;
    cancelled) echo rerun; return ;;
    missing) echo retrigger; return ;;
    pending) echo wait; return ;;
  esac
  # The active main ruleset uses strict required status checks. GitHub will not
  # merge an auto-merge PR whose validated head is behind main. The early
  # behind branch above handles freshness; pending validation always waits.
  [[ "$state" == behind ]] && { echo update-branch; return; }
  [[ "$state" == unknown ]] && { echo wait; return; }
  if [[ "$draft" == true || "$autom" != true ]]; then echo advance; else echo waiting-merge; fi
}

# validation_from_runs: stdin = workflow runs JSON for pr-validation.yml on the
# head SHA (event=pull_request). A completed success is authoritative for the
# required `validate` context even when a duplicate run for the same SHA is
# still queued. GitHub's check rollup has the same context-level semantics.
validation_from_runs() {
  jq -r '
    (.workflow_runs // []) as $runs
    | if ($runs | length) == 0 then "missing"
      elif any($runs[]; .status == "completed" and .conclusion == "success") then "success"
      elif any($runs[]; .status != "completed") then "pending"
      elif any($runs[]; .conclusion == "action_required") then "action_required"
      elif any($runs[]; .conclusion == "failure" or .conclusion == "timed_out") then "failed"
      else "cancelled"
      end'
}

is_branch_update_required() {
  # Only update a branch when GitHub's merge evaluation explicitly says it is
  # out of date. A compare-only "behind" result is insufficient: proactively
  # updating every PR after each merge is what created the validation loop.
  grep -Eqi 'out of date|update (the )?branch|head branch.*(behind|up.to.date)|base branch.*(behind|up.to.date)' "$1"
}

merge_confirmation() { # REST pull JSON -> merged|enabled|inactive
  jq -r 'if .merged_at != null or .state == "closed" then "merged"
         elif .auto_merge != null then "enabled"
         else "inactive" end'
}

# effective_state <rest mergeable_state> <mergeable> <behind_by>: freshness and
# conflict-freeness from REST fields, never GraphQL MERGEABLE. Drafts report
# "draft" and unknown may be transient, so fall back to compare data.
effective_state() {
  local ms="$1" mergeable="$2" behind="$3"
  case "$ms" in
    dirty|behind) echo "$ms"; return ;;
  esac
  if [[ "$mergeable" == false ]]; then echo dirty; return; fi
  if [[ "$ms" == draft || "$ms" == unknown ]]; then
    if [[ "$mergeable" == null || "$mergeable" == "" ]]; then
      [[ "$behind" -gt 0 ]] && echo behind || echo unknown; return
    fi
    [[ "$behind" -gt 0 ]] && echo behind || echo clean; return
  fi
  echo "$ms"
}

api() { gh api "$@"; }
dry() { [[ "${DRY_RUN:-}" == 1 ]]; }

get_state() { # n -> JSON (default {})
  api "repos/${repo}/issues/$1/comments?per_page=100" --paginate \
    --jq '.[] | select(.body|contains("<!-- claude-pr-state ")) | .body' 2>/dev/null \
    | grep -o '<!-- claude-pr-state {.*} -->' | tail -1 | sed 's/^<!-- claude-pr-state //; s/ -->$//' \
    | jq -c . 2>/dev/null || true
}
put_state() { # n json text  (one progress comment per PR, updated in place)
  local n="$1" json="$2" text="$3" id body
  body=$(printf '<!-- claude-pr-state %s -->\n**Automation status:** %s\n\n_Updated by [PR maintenance](%s). Attempts used: %s/%s._' \
    "$json" "$text" "$run_url" "$(jq -r '.attempts // 0' <<<"$json")" "$max_attempts")
  dry && { echo "[dry] state PR #$n: $text"; return 0; }
  id=$(api "repos/${repo}/issues/$n/comments?per_page=100" --paginate \
    --jq '.[] | select(.body|contains("<!-- claude-pr-state ")) | .id' 2>/dev/null | tail -1)
  if [[ -n "$id" ]]; then
    api -X PATCH "repos/${repo}/issues/comments/$id" -f body="$body" >/dev/null
  else
    api -X POST "repos/${repo}/issues/$n/comments" -f body="$body" >/dev/null
  fi
}

merge_flag() {
  local j; j=$(api "repos/${repo}" --jq '[.allow_squash_merge,.allow_merge_commit,.allow_rebase_merge]' 2>/dev/null) || { echo --squash; return; }
  case "$j" in
    '[true,'*) echo --squash ;; '[false,true,'*) echo --merge ;; *) echo --rebase ;;
  esac
}

escalate() { # n issue head kind detail
  local n="$1" issue="$2" head="$3" kind="$4" detail="$5" st key
  st=$(get_state "$n"); st=${st:-"{}"}
  key="${kind}:${head}"
  if jq -e --arg k "$key" '(.escalated // []) | index($k)' <<<"$st" >/dev/null; then return 0; fi
  dry && { echo "[dry] escalate PR #$n $kind"; return 0; }
  gh label create "$label" --color D93F0B --description 'Automation stopped; a human must act' >/dev/null 2>&1 || true
  gh pr edit "$n" --add-label "$label" >/dev/null 2>&1 || true
  st=$(jq -c --arg k "$key" --arg h "$head" '.escalated = ((.escalated // []) + [$k]) | .stopped_head = $h' <<<"$st")
  put_state "$n" "$st" "STOPPED ($kind) at ${head:0:8}"
  gh issue comment "${issue:-$n}" --body "$(printf '@%s PR #%s needs your action.\n\n**Category:** %s\n**Head:** `%s`\n**Detail:** %s\n**Run:** %s\n\nAutomatic attempts have stopped for this head. Push a change, or dispatch "Claude PR Maintenance" for #%s after fixing the cause.' \
    "$owner" "$n" "$kind" "$head" "$detail" "$run_url" "$n")" >/dev/null 2>&1 || true
}

repair_active() {
  # The quoted workflow run-name must contain an unambiguous PR number.
  local n="$1"
  gh run list --workflow pr-conflict-repair.yml --limit 200 --json displayTitle,status 2>/dev/null \
    | jq -e --arg title "Repair PR #${n} (" \
      'any(.[]; (.status == "queued" or .status == "in_progress" or .status == "waiting" or .status == "pending" or .status == "requested") and (.displayTitle | startswith($title)))' >/dev/null
}

is_transient_merge_error() {
  # GitHub may reject --auto while required checks are queued. Treat these
  # as retryable, not as a permanent needs-human-review stop.
  grep -Eqi 'required status check|status checks? (are |is )?(queued|pending|in.progress|expected)|checks? (are |is )?(queued|pending|in.progress|expected)' "$1"
}

process_pr() {
  local n="$1" pr issue head ref draft ms mergeable behind state val autom stopped attempts action st runs
  pr=$(api "repos/${repo}/pulls/$n") || { INFRA=1; echo "PR #$n: API failure" >&2; return; }
  [[ $(jq -r .state <<<"$pr") == open ]] || return 0
  [[ $(jq -r '.head.repo.full_name' <<<"$pr") == "$repo" ]] || { echo "PR #$n: fork, ignored"; return 0; }
  ref=$(jq -r .head.ref <<<"$pr"); head=$(jq -r .head.sha <<<"$pr")
  issue=$(jq -r '.body // ""' <<<"$pr" | grep -o '<!-- claude-issue:[0-9]\+ -->' | head -1 | grep -o '[0-9]\+')
  [[ -n "$issue" && "$ref" =~ ^claude/issue-${issue}-[0-9]+$ ]] || { echo "PR #$n: not a Claude PR, ignored"; return 0; }
  draft=$(jq -r .draft <<<"$pr")
  ms=$(jq -r '.mergeable_state // "unknown"' <<<"$pr")
  mergeable=$(jq -r '.mergeable' <<<"$pr")
  behind=$(api "repos/${repo}/compare/main...${head}" --jq .behind_by 2>/dev/null || echo 0)
  state=$(effective_state "$ms" "$mergeable" "$behind")
  runs=$(api "repos/${repo}/actions/workflows/pr-validation.yml/runs?head_sha=${head}&event=pull_request&per_page=30") \
    || { INFRA=1; echo "PR #$n: cannot list validation runs" >&2; return; }
  val=$(validation_from_runs <<<"$runs")
  autom=$(jq -r '.auto_merge != null' <<<"$pr")
  st=$(get_state "$n"); st=${st:-"{}"}
  attempts=$(jq -r '.attempts // 0' <<<"$st")
  stopped=false
  if jq -e --arg l "$label" 'any(.labels[]; .name == $l)' <<<"$pr" >/dev/null; then
    if [[ -n "${TARGET_PR:-}" ]]; then
      # Owner dispatch: clear the stop and give a fresh budget.
      dry || { gh pr edit "$n" --remove-label "$label" >/dev/null 2>&1; }
      st=$(jq -c '.attempts = 0 | .escalated = [] | del(.stopped_head)' <<<"$st"); attempts=0
    elif [[ $(jq -r '.stopped_head // ""' <<<"$st") == "$head" ]]; then
      stopped=true
    else
      dry || { gh pr edit "$n" --remove-label "$label" >/dev/null 2>&1; }  # head moved: resume
    fi
  fi
  # One-time migration: stops caused by now-fixed automation defects (deleted-file
  # staging, inherited TARGET_PR, premature action_required) get a fresh budget
  # once per FIX_VERSION. Security stops (restricted-conflict, etc.) are untouched.
  if [[ "$stopped" == true && "$(jq -r '.migrated_fix // 0' <<<"$st")" -lt "$FIX_VERSION" ]] \
     && jq -e '(.escalated // []) | all(.[]; test("^(action-required|repair-exhausted|automation-infrastructure-failure|auto-merge-refused):"))' <<<"$st" >/dev/null; then
    st=$(jq -c --argjson v "$FIX_VERSION" --argjson a "$attempts" \
      '.migrated_fix = $v | .migrated_from_attempts = $a | .attempts = 0 | .approval_tries = 0 | .escalated = [] | del(.stopped_head)' <<<"$st")
    attempts=0; stopped=false
    echo "PR #$n: stop invalidated by automation fix v$FIX_VERSION (prior diagnostics kept in history)"
    dry || { gh pr edit "$n" --remove-label "$label" >/dev/null 2>&1; put_state "$n" "$st" "automation fix v$FIX_VERSION invalidated an earlier automation stop; resuming"; }
  fi
  # A newly passing head ends the failure generation.
  if [[ "$val" == success && "$attempts" -gt 0 ]]; then
    st=$(jq -c '.attempts = 0' <<<"$st"); attempts=0
  fi
  action=$(decide "$draft" "$state" "$val" "$autom" "$stopped" "$attempts" "$(jq -r '.approval_tries // 0' <<<"$st")")
  echo "PR #$n: head=${head:0:8} state=$state validation=$val draft=$draft auto_merge=$autom attempts=$attempts -> $action"
  case "$action" in
    stopped|wait|waiting-merge) ;;
    *)
      if (( ACTIONS_STARTED >= 1 )); then
        echo "PR #$n: deferred until the next controlled batch"
        record "$n" "$state" "$val" deferred
        return
      fi
      ACTIONS_STARTED=$((ACTIONS_STARTED + 1)) ;;
  esac
  record "$n" "$state" "$val" "$action"
  dry && return 0

  case "$action" in
    stopped|wait|waiting-merge) ;;
    repair)
      if repair_active "$n"; then
        echo "PR #$n: repair already queued/running (coalesced)"
      else
        # Guard the brief gap between successful dispatch and GitHub indexing
        # the run title; persist the guard in the existing PR status comment.
        local now last
        now=$(date +%s)
        last=$(jq -r --arg h "$head" 'if .repair_dispatch_head == $h then (.repair_dispatch_epoch // 0) else 0 end' <<<"$st")
        if (( now - last < 900 )); then
          echo "PR #$n: repair was recently dispatched for this head; awaiting visibility/outcome"
        else
          gh workflow run pr-conflict-repair.yml -f pr_number="$n" >/dev/null 2>&1 \
            || { INFRA=1; echo "PR #$n: repair dispatch failed" >&2; return; }
          st=$(jq -c --arg h "$head" --argjson t "$now" \
            '.repair_dispatch_head = $h | .repair_dispatch_epoch = $t' <<<"$st")
          put_state "$n" "$st" "repair dispatched ($state / validation $val)" \
            || { INFRA=1; echo "PR #$n: could not persist dispatch state" >&2; return; }
        fi
      fi ;;
    exhausted) escalate "$n" "$issue" "$head" "repair-exhausted" "Validation=$val, branch state=$state after $attempts automated repair attempts." ;;
    resync-approval)
      # Bounded (once per head): a trusted-token sync event; GitHub still decides
      # whether a human approval is genuinely required (then escalate-approval).
      st=$(jq -c '.approval_tries = ((.approval_tries // 0) + 1)' <<<"$st")
      if [[ "$state" == behind ]]; then
        api -X PUT "repos/${repo}/pulls/$n/update-branch" -f expected_head_sha="$head" >/dev/null 2>&1 || echo "PR #$n: update-branch refused"
      else
        gh pr close "$n" >/dev/null 2>&1 && gh pr reopen "$n" >/dev/null 2>&1 || INFRA=1
      fi
      put_state "$n" "$st" "approval-required validation: trusted re-sync attempted for ${head:0:8}" ;;
    escalate-approval)
      escalate "$n" "$issue" "$head" "action-required" "GitHub requires approval before validation runs for this commit. Confirm CLAUDE_WORKFLOW_TOKEN belongs to a user with write access and that the repository's Actions approval policy does not require approval for this actor; then approve the run once in the Actions tab: ${GITHUB_SERVER_URL:-https://github.com}/${repo}/pull/${n}/checks" ;;
    rerun)
      gh run list --workflow pr-validation.yml --commit "$head" --limit 5 --json databaseId,conclusion,event \
        --jq '[.[]|select(.event=="pull_request" and .conclusion=="cancelled")][0].databaseId // empty' \
        | { read -r id; [[ -n "$id" ]] && gh run rerun "$id" >/dev/null 2>&1; } || INFRA=1 ;;
    retrigger)
      # No pull_request run exists for this head (bot push that did not fire,
      # or a lost event). Close/reopen is the supported way to re-emit it.
      if [[ $(jq -r '.reopen // 0' <<<"$st") -lt 2 ]]; then
        gh pr close "$n" >/dev/null 2>&1 && gh pr reopen "$n" >/dev/null 2>&1 \
          && put_state "$n" "$(jq -c '.reopen = ((.reopen // 0) + 1)' <<<"$st")" "validation re-triggered for ${head:0:8}" || INFRA=1
      else
        escalate "$n" "$issue" "$head" "validation-never-ran" "No pull_request validation run exists for this head after 2 re-triggers. Check Actions is enabled and the push token can trigger workflows."
      fi ;;
    update-branch)
      if api -X PUT "repos/${repo}/pulls/$n/update-branch" -f expected_head_sha="$head" >/dev/null 2>&1; then
        st=$(jq -c --arg h "$head" '.branch_update_source_head = $h' <<<"$st")
        put_state "$n" "$st" "strict required checks require an up-to-date branch; updated once and awaiting validation for the new head"
      else
        echo "PR #$n: required branch update was refused (head moved or conflict); next sweep re-evaluates"
      fi ;;
    advance)
      if [[ "$draft" == true ]]; then
        # Marking ready emits ready_for_review; validation may queue again.
        if ! gh pr ready "$n" >/tmp/pr-ready-$n.err 2>&1; then
          escalate "$n" "$issue" "$head" "ready-refused" "$(tail -c 400 /tmp/pr-ready-$n.err)"
          return
        fi
        put_state "$n" "$st" "marked ready; waiting for required validation before merging"
        return
      fi
      if ! gh pr merge "$n" --auto "$(merge_flag)" --match-head-commit "$head" >/tmp/automerge-$n.err 2>&1; then
        if is_transient_merge_error "/tmp/automerge-$n.err"; then
          echo "PR #$n: merge deferred because required validation is queued/pending"
          put_state "$n" "$st" "merge deferred: required validation pending (automatic retry next sweep)"
        elif is_branch_update_required "/tmp/automerge-$n.err"; then
          if api -X PUT "repos/${repo}/pulls/$n/update-branch" -f expected_head_sha="$head" >/dev/null 2>&1; then
            st=$(jq -c --arg h "$head" '.branch_update_source_head = $h' <<<"$st")
            put_state "$n" "$st" "GitHub required a branch update; updated once and awaiting validation for the new head"
          else
            echo "PR #$n: required branch update was refused; next sweep re-evaluates"
            put_state "$n" "$st" "merge blocked: GitHub requires a branch update, but the update was not accepted yet"
          fi
        else
          # Avoid permanently stopping a valid PR on a transient GraphQL
          # merge/ruleset response. Re-evaluate it on the next sweep.
          echo "PR #$n: auto-merge request refused; retrying next sweep: $(tail -c 400 /tmp/automerge-$n.err)"
          put_state "$n" "$st" "auto-merge request refused; retrying next sweep"
          INFRA=1
        fi
      else
        local post outcome
        post=$(api "repos/${repo}/pulls/$n") || { INFRA=1; echo "PR #$n: cannot verify auto-merge request" >&2; return; }
        outcome=$(merge_confirmation <<<"$post")
        case "$outcome" in
          merged) put_state "$n" "$st" "merged (GitHub merged immediately after required checks passed)" ;;
          enabled) put_state "$n" "$st" "auto-merge requested and confirmed; waiting for GitHub merge eligibility" ;;
          *)
            echo "PR #$n: gh pr merge exited successfully but REST reports no merge or auto-merge request"
            put_state "$n" "$st" "merge blocked: GitHub did not confirm auto-merge; retrying on the next sweep"
            INFRA=1 ;;
        esac
      fi ;;
  esac
}

REPORT_ROWS=()
record() { REPORT_ROWS+=("$(jq -nc --argjson pr "$1" --arg state "$2" --arg val "$3" --arg action "$4" '{pr:$pr,state:$state,validation:$val,action:$action}')"); }

write_report() {
  local rows="[]"
  ((${#REPORT_ROWS[@]})) && rows=$(printf '%s\n' "${REPORT_ROWS[@]}" | jq -sc .)
  jq -n --argjson rows "$rows" '{
    open_claude_prs: ($rows|length),
    validating: ([$rows[]|select(.validation=="pending")]|length),
    repairing: ([$rows[]|select(.action=="repair")]|length),
    behind: ([$rows[]|select(.state=="behind")]|length),
    conflicted: ([$rows[]|select(.state=="dirty")]|length),
    waiting_for_merge: ([$rows[]|select(.action=="waiting-merge" or .action=="advance")]|length),
    stopped_for_human: ([$rows[]|select(.action=="stopped" or .action=="exhausted" or .action=="escalate-approval")]|length),
    prs: $rows}' >"$REPORT"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    { echo '### Claude PR maintenance'; echo '```json'; cat "$REPORT"; echo '```'; } >>"$GITHUB_STEP_SUMMARY"
  fi
}

macos_work_pending() {
  jq -e 'any(.workflow_runs[]?;
    (.path // "" | test("/(ios|pr-validation|pr-conflict-repair|issue-to-pr)\\.yml$")))' >/dev/null
}

main() {
  local prs n status runs orphan_jobs quarantine="${QUARANTINED_WORKFLOW_RUN_ID:-}"
  # The serialized reconciler admits work only when macOS workflows are idle.
  # Separate status queries keep old active jobs visible even after many runs.
  for status in in_progress queued pending waiting requested; do
    runs=$(api "repos/${repo}/actions/runs?status=${status}&per_page=100") || {
      echo 'Cannot verify macOS capacity; deferring all changes' >&2; exit 1;
    }
    # Owner-reviewed exception for a GitHub orphan that cannot be cancelled.
    # Never ignore an in-progress run or a run with an actual queued job.
    if [[ "$status" == queued && "$quarantine" =~ ^[0-9]+$ ]] &&
       jq -e --arg id "$quarantine" 'any(.workflow_runs[]?; (.id|tostring) == $id)' <<<"$runs" >/dev/null; then
      orphan_jobs=$(api "repos/${repo}/actions/runs/$quarantine/jobs") || exit 1
      if jq -e '.total_count == 0 and (.jobs|length) == 0' <<<"$orphan_jobs" >/dev/null; then
        echo "Quarantined GitHub orphan $quarantine has zero jobs; ignoring its stale queue record"
        runs=$(jq --arg id "$quarantine" '.workflow_runs |= map(select((.id|tostring) != $id))' <<<"$runs")
      fi
    fi
    if macos_work_pending <<<"$runs"; then
      echo "macOS work is $status; preserving release priority and deferring this batch"
      write_report
      exit 0
    fi
  done
  if [[ -n "${TARGET_PR:-}" ]]; then prs="$TARGET_PR"
  else prs=$(gh pr list --state open --base main --limit 200 --json number --jq 'sort_by(.number) | .[].number') || { echo 'cannot list PRs' >&2; exit 1; }
  fi
  for n in $prs; do process_pr "$n"; done
  write_report
  if [[ "$INFRA" == 1 ]]; then echo 'Infrastructure failure while reconciling; see log' >&2; exit 1; fi
  exit 0
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
