#!/usr/bin/env bash
# Repository-local intake controller. It is the sole macOS dispatcher and
# maintains one durable reservation per repository.
set -euo pipefail
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"; api="repos/${repo}"
ensure_label() { gh label create "$1" --repo "$repo" --color "$2" --description "$3" --force >/dev/null; }
ensure_label ai-ready AAAAAA 'Admitted to the controlled coding queue'
ensure_label priority-high B60205 'Owner-approved priority queue override; admits before normal eligible issues'
ensure_label intake-running 1D76DB 'Repository controller has reserved this issue for implementation'
ensure_label intake-blocked D93F0B 'Pre-PR automation stopped; explicit owner retry or issue rework required'
ensure_label retry-ai FBCA04 'Owner-authorized retry request; handled by the intake controller'
ensure_label blocked-by-dependency 5319E7 'Waiting for an explicitly declared prerequisite PR to merge'

# The controller workflow is serialized, and any active reservation is a
# repository-wide lock: a second sweep cannot race the delayed job listing.
active=$(gh issue list --repo "$repo" --state open --limit 1000 --json number,labels --jq '.[] | select(any(.labels[]?.name; . == "intake-running")) | .number' | head -1)
if [[ -n "$active" ]]; then echo "Repository reservation held by #${active}."; exit 0; fi

macos_capacity_available() {
  local status run_id jobs all_jobs='[]'
  for status in in_progress queued pending waiting requested; do
    while IFS= read -r run_id; do
      [[ -z "$run_id" ]] && continue
      jobs=$(gh api --paginate "${api}/actions/runs/${run_id}/jobs?per_page=100" | jq -s 'map(.jobs // []) | add')
      all_jobs=$(jq --argjson page "$jobs" '. + $page' <<<"$all_jobs")
    done < <(gh api --paginate "${api}/actions/runs?status=${status}&per_page=100" --jq '.workflow_runs[]?.id')
  done
  ! jq -e 'any(.[]; (.status == "queued" or .status == "in_progress") and any(.labels[]?; . == "xcode-27"))' <<<"$all_jobs" >/dev/null
}

# Release only explicit, one-way dependencies when the prerequisite's linked
# implementation PR merges. Closing an issue alone never unlocks a child.
merged_bodies=$(gh pr list --repo "$repo" --state merged --base main --limit 1000 --json body --jq '.[].body // ""')
while IFS= read -r child; do
  body=$(gh issue view "$child" --repo "$repo" --json body --jq '.body // ""')
  mapfile -t parents < <(grep -oE '<!-- claude-depends-on: #[0-9]+ -->' <<<"$body" | sed -E 's/.*#([0-9]+).*/\1/')
  ((${#parents[@]})) || continue
  released=true
  for parent in "${parents[@]}"; do grep -Fq "<!-- claude-issue:${parent} -->" <<<"$merged_bodies" || released=false; done
  if [[ "$released" == true ]]; then
    gh issue edit "$child" --repo "$repo" --remove-label blocked-by-dependency >/dev/null
    gh issue comment "$child" --repo "$repo" --body "<!-- claude-dependency-released:${parent} -->
**Queue dependency released:** every explicitly linked prerequisite implementation PR merged; this issue is eligible for controller admission." >/dev/null
  fi
done < <(gh issue list --repo "$repo" --state open --limit 1000 --json number,labels --jq '.[] | select(any(.labels[]?.name; . == "blocked-by-dependency")) | .number')

macos_capacity_available || { echo 'Actual xcode-27 capacity is occupied.'; exit 0; }
all_pr_bodies=$(gh pr list --repo "$repo" --state all --base main --limit 1000 --json body --jq '.[].body // ""')
issues=$(gh issue list --repo "$repo" --state open --limit 1000 --json number,author,labels,createdAt --jq '
sort_by([if any(.labels[]?.name; . == "priority-high") then 0 else 1 end, .createdAt, .number])[] | select(.author.login == "johnarleyburns")
| select(any(.labels[]?.name; . == "awaiting-ci-authorization" or . == "needs-human-review" or . == "tracking" or . == "blocked-by-dependency" or . == "intake-running" or . == "intake-retry-deferred" or . == "ready-for-qa") | not)
| select((any(.labels[]?.name; . == "intake-blocked") and any(.labels[]?.name; . == "retry-ai")) or any(.labels[]?.name; . == "intake-blocked") | not) | .number')
for issue in $issues; do
  grep -Fq "<!-- claude-issue:${issue} -->" <<<"$all_pr_bodies" && continue
  macos_capacity_available || exit 0
  attempt="$(date +%s)-${RANDOM}${RANDOM}"; marker="<!-- claude-intake-reservation issue=${issue} attempt=${attempt} -->"
  gh issue edit "$issue" --repo "$repo" --add-label intake-running --remove-label retry-ai >/dev/null
  reservation=$(printf '%s\n**Issue intake reservation:** controller-owned, awaiting dispatch confirmation.\n\nAttempt: `%s`' "$marker" "$attempt")
  comment_url=$(gh api --method POST "${api}/issues/${issue}/comments" -f body="$reservation" --jq '.url')
  response=$(gh api --method POST "${api}/actions/workflows/issue-to-pr.yml/dispatches" -f ref=main -f "inputs[issue_number]=${issue}" -f "inputs[attempt_id]=${attempt}" -F return_run_details=true 2>&1) || {
    gh issue edit "$issue" --repo "$repo" --add-label intake-blocked --add-label needs-human-review --remove-label intake-running >/dev/null || true
    gh api --method PATCH "$comment_url" -f body="$reservation

**Issue intake status:** dispatch outcome unknown. No automatic retry will occur; inspect this controller run, then apply `retry-ai` for one new attempt." >/dev/null || true
    echo "$response" >&2; exit 1; }
  run_id=$(jq -r '.workflow_run.id // .id // empty' <<<"$response")
  if [[ -z "$run_id" ]]; then
    gh issue edit "$issue" --repo "$repo" --add-label intake-blocked --add-label needs-human-review --remove-label intake-running >/dev/null || true
    gh api --method PATCH "$comment_url" -f body="$reservation

**Issue intake status:** dispatch response lacked a run ID. No automatic retry will occur; apply `retry-ai` after review." >/dev/null || true
    echo '::error::Dispatch did not return an authoritative run ID' >&2; exit 1
  fi
  gh api --method PATCH "$comment_url" -f body="$reservation

**Issue intake reservation:** dispatched [workflow run ${run_id}](${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${run_id}). Only this attempt may allocate the macOS worker." >/dev/null
  echo "Admitted #${issue}, attempt ${attempt}, run ${run_id}; stopping after one."; exit 0
done
echo 'No eligible owner-authored issue requires admission.'
