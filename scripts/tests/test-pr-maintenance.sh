#!/usr/bin/env bash
# Headless regression tests for .github/scripts/pr-maintenance.sh decision logic
# and a mocked-gh end-to-end sweep. No network, no simulator.
set -uo pipefail
cd "$(cd "$(dirname "$0")/../.." && pwd)"
# Hermetic: never inherit repair-job state (e.g. TARGET_PR) or real credentials.
unset TARGET_PR DRY_RUN GITHUB_RUN_ID GITHUB_STEP_SUMMARY REPORT_FILE
export GH_TOKEN=mock-token GITHUB_TOKEN=mock-token GITHUB_REPOSITORY=o/r
# shellcheck disable=SC1091
source .github/scripts/pr-maintenance.sh
fails=0
eq() { [[ "$2" == "$3" ]] && echo "ok   $1" || { echo "FAIL $1: expected '$3' got '$2'"; fails=$((fails+1)); }; }

# decide <draft> <state> <val> <automerge> <stopped> <attempts>
eq "behind+success+automerge -> update once"       "$(decide false behind success true false 0)" update-branch
eq "behind+success -> update before merge"         "$(decide false behind success false false 0)" update-branch
eq "draft success clean -> advance"                 "$(decide true clean success false false 0)" advance
eq "ready success no automerge -> advance"          "$(decide false clean success false false 0)" advance
eq "ready success automerge -> waiting-merge"       "$(decide false clean success true false 0)" waiting-merge
eq "dirty -> repair"                                "$(decide false dirty success true false 0)" repair
eq "failed validation, clean -> repair"             "$(decide false clean failed false false 1)" repair
eq "failed, 3 attempts -> exhausted"                "$(decide false clean failed false false 3)" exhausted
eq "action_required first -> resync"               "$(decide true clean action_required false false 0)" resync-approval
eq "action_required after resync -> escalate"      "$(decide true clean action_required false false 0 1)" escalate-approval
eq "draft behind action_required -> resync"        "$(decide true behind action_required false false 0)" resync-approval
eq "draft dirty action_required -> repair"         "$(decide true dirty action_required false false 0)" repair
eq "cancelled -> rerun"                             "$(decide false clean cancelled false false 0)" rerun
eq "missing check -> retrigger"                     "$(decide false clean missing false false 0)" retrigger
eq "pending -> wait"                                "$(decide false behind pending true false 0)" wait
eq "behind cancelled -> update current infrastructure" "$(decide false behind cancelled true false 0)" update-branch
eq "behind failed -> update before repair"           "$(decide false behind failed true false 0)" update-branch
eq "unknown mergeability -> wait"                   "$(decide false unknown success true false 0)" wait
eq "stopped head -> stopped"                        "$(decide false dirty failed false true 3)" stopped

# REST mergeable_state vs GraphQL MERGEABLE: behind must be detected.
eq "REST behind"                  "$(effective_state behind true 2)" behind
eq "draft but behind main"        "$(effective_state draft true 4)" behind
eq "draft up to date"             "$(effective_state draft true 0)" clean
eq "draft with conflicts"         "$(effective_state draft false 0)" dirty
eq "unknown mergeable null"       "$(effective_state unknown null 0)" unknown
eq "clean passthrough"            "$(effective_state clean true 0)" clean
eq "blocked passthrough"          "$(effective_state blocked true 0)" blocked

run() { jq -nc --arg s "$1" --arg c "$2" --arg t "${3:-2026-01-01T00:00:00Z}" '{workflow_runs:[{status:$s,conclusion:(if $c=="" then null else $c end),created_at:$t}]}'; }
eq "no runs -> missing"        "$(echo '{"workflow_runs":[]}' | validation_from_runs)" missing
eq "queued -> pending"         "$(run queued '' | validation_from_runs)" pending
eq "success"                   "$(run completed success | validation_from_runs)" success
eq "failure"                   "$(run completed failure | validation_from_runs)" failed
eq "action_required"           "$(run completed action_required | validation_from_runs)" action_required
eq "cancelled"                 "$(run completed cancelled | validation_from_runs)" cancelled
eq "successful plus redundant queued -> success" "$(jq -nc '{workflow_runs:[{status:"completed",conclusion:"success"},{status:"queued",conclusion:null}]}' | validation_from_runs)" success
eq "failed plus successful -> success" "$(jq -nc '{workflow_runs:[{status:"completed",conclusion:"failure"},{status:"completed",conclusion:"success"}]}' | validation_from_runs)" success
eq "stale SHA runs are absent -> missing" "$(echo '{"workflow_runs":[]}' | validation_from_runs)" missing
eq "branch update error is recognized" "$(printf 'head branch is out of date; update branch' >"$PWD/.tmp-merge-error"; is_branch_update_required "$PWD/.tmp-merge-error" && echo yes || echo no)" yes
rm -f .tmp-merge-error
eq "auto merge confirmed" "$(echo '{"state":"open","auto_merge":{"enabled_by":{"login":"bot"}}}' | merge_confirmation)" enabled
eq "immediate merge confirmed" "$(echo '{"state":"closed","merged_at":"2026-01-01T00:00:00Z","auto_merge":null}' | merge_confirmation)" merged
eq "successful command but inactive is diagnosed" "$(echo '{"state":"open","auto_merge":null}' | merge_confirmation)" inactive
eq "active release reserves capacity" "$(echo '{"workflow_runs":[{"path":".github/workflows/ios.yml"}]}' | macos_work_pending && echo busy || echo idle)" busy
eq "maintenance does not reserve macOS capacity" "$(echo '{"workflow_runs":[{"path":".github/workflows/pr-maintenance.yml"}]}' | macos_work_pending && echo busy || echo idle)" idle
eq "idle queue admits one batch" "$(echo '{"workflow_runs":[]}' | macos_work_pending && echo busy || echo idle)" idle

# Mocked end-to-end sweep: a successfully validated branch behind strict
# required checks must update once, then wait for the resulting SHA.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/gh" <<'MOCK'
#!/usr/bin/env bash
echo "gh $*" >>"$MOCK_LOG"
a="$*"
case "$a" in
  *"actions/runs?status="*)
    if [[ "${MOCK_BUSY:-}" == 1 ]]; then
      echo '{"workflow_runs":[{"path":".github/workflows/ios.yml"}]}'
    elif [[ "${MOCK_BUSY:-}" == error ]]; then exit 1
    else echo '{"workflow_runs":[]}'
    fi ;;
  "pr list"*) printf '97\n5\n6\n' ;;
  "api repos/o/r/pulls/97") echo '{"state":"open","head":{"repo":{"full_name":"o/r"},"ref":"claude/issue-12-34","sha":"abc12345"},"body":"<!-- claude-issue:12 -->","draft":false,"mergeable_state":"behind","mergeable":true,"auto_merge":{"x":1},"labels":[]}' ;;
  "api repos/o/r/pulls/5") echo '{"state":"open","head":{"repo":{"full_name":"fork/r"},"ref":"claude/issue-1-1","sha":"f"},"body":"<!-- claude-issue:1 -->","draft":false,"labels":[]}' ;;
  "api repos/o/r/pulls/6") echo '{"state":"open","head":{"repo":{"full_name":"o/r"},"ref":"feature/x","sha":"g"},"body":"","draft":false,"labels":[]}' ;;
  *compare*) echo 3 ;;
  *"pr-validation.yml/runs"*) echo '{"workflow_runs":[{"status":"completed","conclusion":"success","created_at":"2026-01-01T00:00:00Z"}]}' ;;
  *"-X PUT"*update-branch*) echo '{}' ;;
  *comments*) ;;
  *) echo '{}' ;;
esac
MOCK
chmod +x "$tmp/gh"
export MOCK_LOG="$tmp/log" PATH="$tmp:$PATH"
repo=o/r; REPORT="$tmp/report.json"
: >"$MOCK_LOG"
( main >"$tmp/out" 2>&1 ); rc=$?
eq "sweep exit code" "$rc" 0
[[ $rc -ne 0 ]] && cat "$tmp/out"
grep -q 'update-branch' "$MOCK_LOG" && r=yes || r=no
eq "strict behind branch is updated once" "$r" yes
grep -Eq 'pr (ready|merge|close)' "$MOCK_LOG" && r=yes || r=no
eq "no ready/merge/close on behind PR" "$r" no
eq "fork/non-Claude ignored" "$(jq '.open_claude_prs' "$tmp/report.json")" 1
eq "behind counted" "$(jq '.behind' "$tmp/report.json")" 1
: >"$MOCK_LOG"
ACTIONS_STARTED=1
process_pr 97 >"$tmp/budget-out" 2>&1
grep -q 'update-branch' "$MOCK_LOG" && r=yes || r=no
eq "exhausted batch budget never updates another branch" "$r" no
ACTIONS_STARTED=0
: >"$MOCK_LOG"
( export MOCK_BUSY=1; main >"$tmp/busy-out" 2>&1 ); rc=$?
eq "active release defers reconciliation successfully" "$rc" 0
grep -q 'pr list' "$MOCK_LOG" && r=yes || r=no
eq "active release prevents even starting the PR sweep" "$r" no
( export MOCK_BUSY=error; main >"$tmp/error-out" 2>&1 ); rc=$?
eq "unreadable capacity fails closed" "$rc" 1

# Git: modify/delete conflict resolved by accepting main's deletion, filenames with spaces.
if [[ -z "${SKIP_GIT_TESTS:-}" ]]; then
  src=$(sed -n '/^staged_merge_paths_ok()/,/^}/p;/^stage_resolved()/,/^}/p' .github/scripts/pr-conflict-repair.sh)
  ci_authorized=false; ci_paths=(); sensitive_re='\.p12$'
  path_allowed() { [[ "$1" != .github/* ]] && ! grep -Eiq "$sensitive_re" <<<"$1"; }
  eval "$src"
  g="$tmp/g"; git init -q -b main "$g"; (
    cd "$g" && git config user.email t@t && git config user.name t
    echo a >current_status.md; echo b >"my file.txt"; mkdir -p .github/workflows; echo w >.github/workflows/x.yml
    git add -A && git commit -qm base
    git checkout -qb feat && echo c >>current_status.md && echo d >>"my file.txt" && git commit -qam feat
    git checkout -q main && git rm -q current_status.md && echo w2 >.github/workflows/x.yml && git commit -qam main
    git update-ref refs/remotes/origin/main main
    git checkout -q feat
    git merge --no-edit origin/main >/dev/null 2>&1
    cf=(); while IFS= read -r -d '' f; do cf+=("$f"); done < <(git diff --name-only --diff-filter=U -z)
    rm -f current_status.md
    stage_resolved "${cf[@]}" && [[ -z "$(git ls-files -u)" ]] && staged_merge_paths_ok && git commit -qm merge && echo ok
  ) >"$tmp/gitout" 2>&1
  eq "modify/delete resolved + upstream .github allowed" "$(tail -1 "$tmp/gitout")" ok
  [[ ! -e "$g/current_status.md" ]] && r=yes || r=no
  eq "deleted file not recreated" "$r" yes
  ( cd "$g" && git checkout -q feat && echo evil >.github/workflows/x.yml && git add -A && staged_merge_paths_ok ) 2>/dev/null && r=allowed || r=rejected
  eq "unauthorized workflow edit rejected" "$r" rejected
fi

[[ $fails -eq 0 ]] && echo "all passed" || { echo "$fails failure(s)"; exit 1; }
