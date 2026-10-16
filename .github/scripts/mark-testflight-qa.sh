#!/usr/bin/env bash
# Called only after the TestFlight upload and tests succeeded.
set -Eeuo pipefail
repo=${GITHUB_REPOSITORY:?}
sha=${GITHUB_SHA:?}
run=${GITHUB_RUN_ID:?}
url="${GITHUB_SERVER_URL:-https://github.com}/$repo/actions/runs/$run"
# Last successful main push deployment, excluding this run. A successful ios.yml
# run implies both the TestFlight upload and deployment-report job succeeded.
previous=$(gh run list --repo "$repo" --workflow ios.yml --branch main --limit 100 \
  --json databaseId,headSha,conclusion,event \
  --jq "[.[] | select(.databaseId != $run and .event == \"push\" and .conclusion == \"success\")][0].headSha // empty")
if [[ -n "$previous" && "$previous" != "$sha" ]]; then
  commits=$(gh api --paginate "repos/$repo/compare/$previous...$sha" --jq '.commits[].sha')
else
  # Initial deployment, or rerun of the same commit: only mark this SHA.
  commits="$sha"
fi
# Commit-to-PR association also handles squash merges and multiple PRs per build.
declare -A prs=()
while IFS= read -r commit; do
  [[ -n "$commit" ]] || continue
  while IFS= read -r pr; do
    [[ -n "$pr" ]] && prs["$pr"]=1
  done < <(gh api "repos/$repo/commits/$commit/pulls" \
    --jq '.[] | select(.merged_at != null and .base.ref == "main") | .number')
done <<< "$commits"
gh label create ready-for-qa --repo "$repo" --color 0E8A16 \
  --description 'Merged change uploaded to TestFlight; Apple processing may still be pending' --force >/dev/null
for pr in "${!prs[@]}"; do
  body=$(gh api "repos/$repo/pulls/$pr" --jq '.body // ""')
  issue=$(printf '%s\n' "$body" | sed -n 's/.*<!-- claude-issue:\([0-9][0-9]*\) -->.*/\1/p' | head -1)
  [[ -n "$issue" ]] || { echo "PR #$pr has no claude-issue marker; skipping"; continue; }
  gh issue edit "$issue" --repo "$repo" --add-label ready-for-qa
  # The traceability recorder owns the idempotent delivery comment.  Retain
  # the historical upload-stage label for now, while its comment explicitly
  # says that upload is not tester availability.
  echo "Issue #$issue received legacy ready-for-qa upload label (PR #$pr)"
done
