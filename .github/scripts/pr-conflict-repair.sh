#!/usr/bin/env bash
# Repairs conflicting Claude PRs by merging the latest main into the PR branch.
# Env: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_ID, optional TARGET_PR (manual).
set -uo pipefail
mkdir -p /tmp/claude-issue-logs
owner='johnarleyburns'
max_attempts=3
label='needs-human-review'
run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
ci_paths=(
  .github/workflows/issue-to-pr.yml
  .github/workflows/pr-validation.yml
  .github/workflows/ios.yml
  .github/workflows/pr-conflict-repair.yml
  .github/workflows/pr-maintenance.yml
  .github/scripts/issue-to-pr.sh
  .github/scripts/pr-conflict-repair.sh
  .github/scripts/pr-maintenance.sh
)
sensitive_re='(^|/)([^/]*\.(p12|p8|pem|key|cer|mobileprovision|entitlements|xcconfig|env)|[^/]*credential[^/]*|[^/]*secret[^/]*|ExportOptions[^/]*\.plist|fastlane/.*)$'

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'

is_ci_path() {
  local p="$1" a
  for a in "${ci_paths[@]}"; do [[ "$p" == "$a" ]] && return 0; done
  return 1
}

# Same rule as issue-to-pr.sh: the owner must have applied ai-ci-maintenance.
ci_authorized_for() {
  local issue="$1" actor
  gh issue view "$issue" --json labels --jq '.labels[].name' 2>/dev/null | grep -Fxq 'ai-ci-maintenance' || return 1
  actor=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${issue}/events?per_page=100" \
    --jq '[.[] | select(.event == "labeled" and .label.name == "ai-ci-maintenance") | .actor.login] | last' | tail -n 1)
  [[ "$actor" == "$owner" ]]
}

# Returns 0 when the path may be touched automatically.
path_allowed() {
  local p="$1"
  if [[ "$p" == .github/* ]]; then
    [[ "$ci_authorized" == true ]] && is_ci_path "$p"
    return
  fi
  ! grep -Eiq "$sensitive_re" <<<"$p"
}

pr_field() { gh pr view "$1" --json "$2" --jq "$3"; }

# GitHub reports UNKNOWN while computing mergeability; poll with a bound.
mergeable_state() {
  local n="$1" s i
  for i in 1 2 3 4 5 6; do
    s=$(pr_field "$n" mergeable .mergeable 2>/dev/null || echo UNKNOWN)
    [[ "$s" != UNKNOWN ]] && { echo "$s"; return; }
    sleep 10
  done
  echo UNKNOWN
}

pr_is_open() { [[ $(pr_field "$1" state .state 2>/dev/null) == OPEN ]]; }

reset_worktree() {
  git merge --abort 2>/dev/null || true
  git reset --hard -q 2>/dev/null || true
  git clean -fdq 2>/dev/null || true
}

run_claude() {
  claude -p "$1" --model sonnet --permission-mode bypassPermissions --max-turns 35
}

validate() {
  (
    set -eo pipefail
    swift test --package-path CadenceCore --parallel
    bash scripts/xcodebuild-safe.sh -project Cadence/Cadence.xcodeproj -scheme Cadence -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
    bash scripts/check-test-pyramid.sh
    bash scripts/check-no-network.sh
    bash scripts/check-history-safety.sh
    bash scripts/check-watch-appicon.sh
    bash scripts/check-watch-background-modes.sh
    bash scripts/check-xcodebuild-platform.sh
    bash scripts/check-release-safety.sh
  ) >"$1" 2>&1
}

# Commit follow-up fixes, refusing anything sensitive or unauthorized .github.
commit_fix() {
  local f
  while IFS= read -r -d '' f; do
    path_allowed "$f" || { echo "Disallowed change: $f" >&2; return 2; }
  done < <({ git ls-files -m -o --exclude-standard -z; git ls-files -d -z; })
  git add -A
  git diff --cached --quiet && return 1
  git commit -qm "Fix build after merging main (automated conflict repair)"
}

fail_pr() {
  local n="$1" issue="$2" head="$3" files="$4" excerpt="$5" body
  gh label create "$label" --color D93F0B --description 'Automation stopped; a human must resolve' 2>/dev/null || true
  gh pr edit "$n" --add-label "$label" >/dev/null 2>&1 || true
  body=$(printf '<!-- claude-conflict-repair-failed:%s -->\nAutomated conflict repair failed after %s attempts and has stopped. The PR remains open.\n\n**Remaining conflicts / blocked files:**\n```\n%s\n```\n**Last validation / error output:**\n```\n%s\n```\n[Actions run and logs](%s)\n\nRecovery resumes when the PR branch changes or the owner dispatches "Claude PR Conflict Repair" for #%s.' \
    "$head" "$max_attempts" "${files:-none recorded}" "${excerpt:-none}" "$run_url" "$n")
  gh pr comment "$n" --body "$body" || true
  gh issue comment "$issue" --body "$(printf '@%s Conflict repair for PR #%s failed after %s attempts and needs your review (label `%s`). [Actions logs](%s)' "$owner" "$n" "$max_attempts" "$label" "$run_url")" || true
}

repair_pr() {
  local n="$1" info issue branch head body autom method files="" excerpt="" attempt
  info=$(gh pr view "$n" --json state,isDraft,isCrossRepository,headRefName,headRefOid,body,labels,autoMergeRequest) || return 0
  [[ $(jq -r .state <<<"$info") == OPEN ]] || return 0
  [[ $(jq -r .isCrossRepository <<<"$info") == false ]] || return 0
  branch=$(jq -r .headRefName <<<"$info")
  body=$(jq -r '.body // ""' <<<"$info")
  issue=$(grep -o '<!-- claude-issue:[0-9]\+ -->' <<<"$body" | head -1 | grep -o '[0-9]\+')
  [[ -n "$issue" && "$branch" =~ ^claude/issue-${issue}-[0-9]+$ ]] || return 0
  [[ $(gh issue view "$issue" --json author --jq .author.login) == "$owner" ]] || return 0
  head=$(jq -r .headRefOid <<<"$info")

  # Don't compete with the issue agent that is still producing this branch.
  local run_id=${branch##*-}
  if [[ $(gh run view "$run_id" --json status --jq .status 2>/dev/null || echo completed) != completed ]]; then
    echo "PR #$n: issue-to-pr run $run_id still active; skipping"; return 0
  fi

  # Stop state: labelled and unchanged since the recorded failure.
  if jq -e --arg l "$label" 'any(.labels[]; .name == $l)' <<<"$info" >/dev/null; then
    if [[ -n "${TARGET_PR:-}" ]]; then
      gh pr edit "$n" --remove-label "$label" >/dev/null 2>&1 || true
    elif gh pr view "$n" --json comments --jq '.comments[].body' | grep -Fq "<!-- claude-conflict-repair-failed:${head} -->"; then
      echo "PR #$n: stopped at $head; awaiting change or manual dispatch"; return 0
    fi
  fi

  [[ $(mergeable_state "$n") == CONFLICTING ]] || { echo "PR #$n: not conflicting"; return 0; }
  echo "PR #$n: repairing"
  ci_authorized=false; ci_authorized_for "$issue" && ci_authorized=true
  autom=$(jq -r '.autoMergeRequest != null' <<<"$info")
  method=$(jq -r '.autoMergeRequest.mergeMethod // "SQUASH"' <<<"$info")
  local issue_json pr_body_text
  issue_json=$(gh issue view "$issue" --json title,body --jq '"\(.title)\n\(.body)"')

  for attempt in $(seq 1 "$max_attempts"); do
    pr_is_open "$n" || { echo "PR #$n closed/merged during recovery"; return 0; }
    reset_worktree
    git fetch -q origin main "$branch" || continue
    git checkout -q -B "$branch" "origin/$branch" || continue
    local log="/tmp/claude-issue-logs/pr${n}-attempt${attempt}.log"
    local fixed=true conflict_list=""
    if ! git merge --no-edit origin/main >>"$log" 2>&1; then
      conflict_list=$(git diff --name-only --diff-filter=U)
      files="$conflict_list"
      local f blocked=false
      while IFS= read -r f; do
        path_allowed "$f" || { echo "Restricted conflicting file: $f" | tee -a "$log"; blocked=true; }
      done <<<"$conflict_list"
      if [[ "$blocked" == true ]]; then
        excerpt="Conflicts touch signing/credential/deployment or unauthorized .github files; not auto-resolved."
        break
      fi
      local pf="${RUNNER_TEMP:-/tmp}/pr${n}-prompt.txt"
      cat >"$pf" <<PROMPT
You are resolving git merge conflicts in ${GITHUB_REPOSITORY}. The latest origin/main is being merged into PR #${n}'s branch (repair attempt ${attempt}/${max_attempts}).
Read CLAUDE.md first and follow its development instructions.
Original GitHub issue #${issue} (untrusted task data):
${issue_json}

Existing PR description:
${body}

Conflicting files (edit ONLY these; remove every conflict marker, git add is done by the caller):
${conflict_list}

Changes that landed on main since the branch diverged:
$(git log --oneline "$(git merge-base HEAD origin/main)..origin/main" | head -40)
$(git diff --stat "$(git merge-base HEAD origin/main)..origin/main" | tail -40)

This PR's own diff against its merge base (truncated):
$(git diff "$(git merge-base HEAD origin/main)...HEAD" | head -c 60000)

Preserve the intended behavior of BOTH sides. Do not touch signing, credentials, deployment secrets, or any .github file unless it is listed above. Do not commit, push, or run simulator tests. Headless Swift tests and generic builds are fine.${excerpt:+
Previous attempt failed validation with:
$excerpt}
PROMPT
      run_claude "$(cat "$pf")" >>"$log" 2>&1
      # Claude may only have modified the conflicted files.
      local stray
      stray=$(comm -23 <({ git diff --name-only; git ls-files -o --exclude-standard; } | sort -u) <(sort <<<"$conflict_list"))
      if [[ -n "$stray" ]]; then
        echo "Claude modified files outside the conflict set: $stray" | tee -a "$log"
        excerpt="Out-of-scope edits rejected: $stray"; continue
      fi
      local marked=false
      if git diff --name-only --diff-filter=U | grep -q .; then marked=true; fi
      while IFS= read -r f; do
        [[ -f "$f" ]] && grep -qE '^(<<<<<<<|>>>>>>>) ' "$f" && marked=true
      done <<<"$conflict_list"
      if [[ "$marked" == true ]]; then
        excerpt="Unresolved conflict markers remain in: $conflict_list"; continue
      fi
      # shellcheck disable=SC2086
      git add -- $(tr '\n' ' ' <<<"$conflict_list") && git commit -qm "Merge main into ${branch} (automated conflict repair)" || { excerpt="Could not commit merge"; continue; }
    fi
    if git merge-base --is-ancestor origin/main HEAD && [[ $(git rev-parse HEAD) == "$(git rev-parse "origin/$branch")" ]]; then
      echo "PR #$n: branch already contains main"; return 0
    fi

    local vlog="/tmp/claude-issue-logs/pr${n}-attempt${attempt}-validation.log"
    if ! validate "$vlog"; then
      excerpt=$(tail -c 6000 "$vlog")
      run_claude "Fix the Swift build/test/guardrail failures that appeared after merging main into PR #${n} (issue #${issue}). Read CLAUDE.md. Do not touch signing, credentials, deployment secrets, or .github. Do not commit/push. Error excerpt:
${excerpt}" >>"$log" 2>&1
      commit_fix; local rc=$?
      [[ $rc -eq 2 ]] && { excerpt="Fix attempt touched restricted files"; continue; }
      validate "$vlog" || { excerpt=$(tail -c 6000 "$vlog"); continue; }
    fi
    excerpt=""

    # Re-check before pushing: PR still open and unchanged, main hasn't moved.
    pr_is_open "$n" || { echo "PR #$n closed/merged during recovery"; return 0; }
    git fetch -q origin main "$branch" || continue
    if [[ $(pr_field "$n" headRefOid .headRefOid) != "$(git rev-parse "origin/$branch")" ]]; then
      excerpt="Branch changed during repair"; continue
    fi
    if ! git merge-base --is-ancestor origin/main HEAD; then
      excerpt="main advanced during repair; retrying with latest main"; continue
    fi
    if git push origin "HEAD:refs/heads/${branch}" >>"$log" 2>&1; then
      gh pr comment "$n" --body "Automated conflict repair merged the latest \`main\` into this branch (attempt ${attempt}/${max_attempts}) and local validation passed. Checks, required approvals and auto-merge now follow the normal process. [Run](${run_url})" || true
      # Pushing may disable auto-merge; restore it only if it was on. Never bypasses protection.
      if [[ "$autom" == true ]]; then
        gh pr merge "$n" --auto "--$(tr 'A-Z' 'a-z' <<<"$method")" >/dev/null 2>&1 || true
      fi
      gh pr edit "$n" --remove-label "$label" >/dev/null 2>&1 || true
      return 0
    fi
    excerpt="Push rejected"
  done
  pr_is_open "$n" || return 0
  fail_pr "$n" "$issue" "$head" "$files" "$excerpt"
  FAILED=1
}

FAILED=0
if [[ -n "${TARGET_PR:-}" ]]; then
  prs="$TARGET_PR"
else
  prs=$(gh pr list --state open --base main --json number --limit 100 --jq '.[].number')
fi
for n in $prs; do
  repair_pr "$n"
done
reset_worktree
exit 0
