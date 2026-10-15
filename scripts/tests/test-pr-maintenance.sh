#!/usr/bin/env bash
# Headless regression tests for .github/scripts/pr-maintenance.sh decision logic
# and a mocked-gh end-to-end sweep. No network, no simulator.
set -uo pipefail
cd "$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source .github/scripts/pr-maintenance.sh
fails=0
eq() { [[ "$2" == "$3" ]] && echo "ok   $1" || { echo "FAIL $1: expected '$3' got '$2'"; fails=$((fails+1)); }; }

# decide <draft> <state> <val> <automerge> <stopped> <attempts>
eq "PR97 behind+success+automerge -> update-branch" "$(decide false behind success true false 0)" update-branch
eq "draft success clean -> advance"                 "$(decide true clean success false false 0)" advance
eq "ready success no automerge -> advance"          "$(decide false clean success false false 0)" advance
eq "ready success automerge -> waiting-merge"       "$(decide false clean success true false 0)" waiting-merge
eq "dirty -> repair"                                "$(decide false dirty success true false 0)" repair
eq "failed validation, clean -> repair"             "$(decide false clean failed false false 1)" repair
eq "failed, 3 attempts -> exhausted"                "$(decide false clean failed false false 3)" exhausted
eq "action_required never passes"                   "$(decide true clean action_required false false 0)" escalate-approval
eq "cancelled -> rerun"                             "$(decide false clean cancelled false false 0)" rerun
eq "missing check -> retrigger"                     "$(decide false clean missing false false 0)" retrigger
eq "pending -> wait"                                "$(decide false behind pending true false 0)" wait
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
eq "latest run wins" "$(jq -nc '{workflow_runs:[{status:"completed",conclusion:"failure",created_at:"2026-01-01T00:00:00Z"},{status:"completed",conclusion:"success",created_at:"2026-01-02T00:00:00Z"}]}' | validation_from_runs)" success

# Mocked end-to-end sweep: PR #97 is behind with passing validation; a fork PR
# and a non-Claude PR must be ignored; update-branch must be the only write.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/gh" <<'MOCK'
#!/usr/bin/env bash
echo "gh $*" >>"$MOCK_LOG"
a="$*"
case "$a" in
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
eq "PR97 update-branch invoked" "$r" yes
grep -Eq 'pr (ready|merge|close)' "$MOCK_LOG" && r=yes || r=no
eq "no ready/merge/close on behind PR" "$r" no
eq "fork/non-Claude ignored" "$(jq '.open_claude_prs' "$tmp/report.json")" 1
eq "behind counted" "$(jq '.behind' "$tmp/report.json")" 1

[[ $fails -eq 0 ]] && echo "all passed" || { echo "$fails failure(s)"; exit 1; }
