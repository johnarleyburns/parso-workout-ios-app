#!/usr/bin/env bash
# Admit exactly one owner-authored issue that has no implementation PR. This is
# intentionally a slow, repository-local-capacity-aware backstop: it repairs missed
# issue events without recreating a bulk macOS queue. A label is bookkeeping,
# not a trigger; GitHub suppresses workflow events created by GITHUB_TOKEN.
set -euo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
macos_work_pending() {
  jq -e 'any(.workflow_runs[]?;
    (.path // "" | test("/(ios|pr-validation|pr-conflict-repair|issue-to-pr|release-repair)\\.yml$")))' >/dev/null
}

macos_capacity_available() {
  local status runs
  for status in in_progress queued pending waiting requested; do
    runs=$(gh api "repos/${repo}/actions/runs?status=${status}&per_page=100")
    if macos_work_pending <<<"$runs"; then
      echo "macOS work is ${status} in ${repo}; no stranded issue admitted"
      return 1
    fi
  done
}

# Provision this required label defensively so a deleted repository label cannot
# stall every eligible issue again. Preserve an existing label's colour/text.
if ! gh label list --repo "$repo" --limit 100 --json name --jq '.[].name' | grep -Fxq 'ai-ready'; then
  gh label create 'ai-ready' --repo "$repo" --color AAAAAA \
    --description 'Admitted to the controlled coding queue'
fi

macos_capacity_available || exit 0

# Bodies, rather than PR title conventions, are the durable issue-to-PR link.
pr_bodies=$(gh pr list --repo "$repo" --state all --base main --limit 200 --json body --jq '.[] | .body // ""')
issues=$(gh issue list --repo "$repo" --state open --limit 200 \
  --json number,author,labels,createdAt --jq '
    sort_by(.createdAt)[]
    | select(.author.login == "johnarleyburns")
    | select(any(.labels[]?.name;
        . == "awaiting-ci-authorization" or . == "needs-human-review" or
        . == "ready-for-qa") | not)
    | .number')

for issue in $issues; do
  if grep -Fq "<!-- claude-issue:${issue} -->" <<<"$pr_bodies"; then
    continue
  fi
  # Recheck immediately before admission. This repository-local check prevents
  # a second macOS job after a run was queued while listing issues. Other
  # repositories reconcile independently and must never block this repository.
  macos_capacity_available || exit 0
  gh issue edit "$issue" --repo "$repo" --add-label ai-ready
  if ! gh workflow run issue-to-pr.yml --repo "$repo" --ref main -f "issue_number=${issue}"; then
    gh issue edit "$issue" --repo "$repo" --remove-label ai-ready >/dev/null 2>&1 || true
    echo "::error::Could not dispatch Issue to PR for #${issue}; admission was rolled back" >&2
    exit 1
  fi
  echo "Admitted and explicitly dispatched stranded issue #${issue}; intentionally stopping after one."
  exit 0
done

echo 'No stranded owner-authored issues require admission.'
