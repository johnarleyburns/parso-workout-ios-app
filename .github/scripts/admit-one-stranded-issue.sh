#!/usr/bin/env bash
# Admit exactly one owner-authored issue that has never acquired an implementation
# PR. This is intentionally a slow, capacity-aware backstop: it repairs missed
# issue events without recreating a bulk macOS queue.
set -euo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
owner='johnarleyburns'

macos_work_pending() {
  jq -e 'any(.workflow_runs[]?;
    (.path // "" | test("/(ios|pr-validation|pr-conflict-repair|issue-to-pr|release-repair)\\.yml$")))' >/dev/null
}

for status in in_progress queued pending waiting requested; do
  runs=$(gh api "repos/${repo}/actions/runs?status=${status}&per_page=100")
  if macos_work_pending <<<"$runs"; then
    echo "macOS work is ${status}; no stranded issue admitted"
    exit 0
  fi
done

# Bodies, rather than PR title conventions, are the durable issue-to-PR link.
pr_bodies=$(gh pr list --repo "$repo" --state all --base main --limit 200 --json body --jq '.[] | .body // ""')
issues=$(gh issue list --repo "$repo" --state open --limit 200 \
  --json number,author,labels,createdAt --jq '
    sort_by(.createdAt)[]
    | select(.author.login == "johnarleyburns")
    | select(any(.labels[]?.name;
        . == "ai-ready" or . == "awaiting-ci-authorization" or
        . == "needs-human-review" or . == "ready-for-qa") | not)
    | .number')

for issue in $issues; do
  if grep -Fq "<!-- claude-issue:${issue} -->" <<<"$pr_bodies"; then
    continue
  fi
  gh issue edit "$issue" --repo "$repo" --add-label ai-ready
  echo "Admitted stranded issue #${issue}; intentionally stopping after one."
  exit 0
done

echo 'No stranded owner-authored issues require admission.'
