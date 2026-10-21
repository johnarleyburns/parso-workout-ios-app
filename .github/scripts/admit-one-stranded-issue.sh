#!/usr/bin/env bash
# Repository-local intake controller. It is the sole macOS dispatcher and
# maintains one durable reservation per repository.
set -euo pipefail
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"; api="repos/${repo}"
# This is the authoritative admission brake. Workflow conditions alone are not
# enough because manual dispatch and owner-applied labels can otherwise bypass
# a paused queue.
pipeline_enabled="${CLAUDE_PIPELINE_AUTO_ENABLED:-false}"
if [[ "$pipeline_enabled" != true ]]; then
  echo 'Issue admission is paused by CLAUDE_PIPELINE_AUTO_ENABLED.'
  exit 0
fi

# Never start a second implementation lifecycle while a generated PR is open.
# The next worker is admitted only after main's release for the current SHA has
# completed successfully, so it always begins from settled main rather than a
# pre-merge snapshot that would need rebasing.
open_generated_pr=$(gh pr list --repo "$repo" --state open --base main --limit 1000 --json number,body \
  --jq '.[] | select((.body // "") | contains("<!-- claude-issue:")) | .number' | head -1)
if [[ -n "$open_generated_pr" ]]; then
  echo "Generated PR #${open_generated_pr} is still open; admission waits for merge and main release."
  exit 0
fi
main_sha=$(gh api "${api}/git/ref/heads/main" --jq '.object.sha')
release=$(gh api "${api}/actions/runs?head_sha=${main_sha}&per_page=100" | jq '[.workflow_runs[] | select(.name == "iOS Build & TestFlight" or .name == "iOS")] | sort_by(.created_at) | last')
release_status=$(jq -r '.status // empty' <<<"$release")
release_conclusion=$(jq -r '.conclusion // empty' <<<"$release")
if [[ "$release_status" != completed || "$release_conclusion" != success ]]; then
  echo "main ${main_sha} release is not successfully settled (${release_status:-missing}/${release_conclusion:-missing}); admission waits."
  exit 0
fi
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

# Reject malformed or circular dependency metadata before it can silently freeze
# an issue. A dependency must be explicit and every graph edge is one-way.
declare -A dependencies
while IFS= read -r encoded; do
  row=$(base64 --decode <<<"$encoded")
  number=$(jq -r .number <<<"$row")
  refs=$(jq -r '.body // ""' <<<"$row" | grep -oE '<!-- claude-depends-on: #[0-9]+ -->' | sed -E 's/.*#([0-9]+).*/\1/' | tr '\n' ' ' || true)
  dependencies["$number"]="$refs"
done < <(gh issue list --repo "$repo" --state open --limit 1000 --json number,body --jq '.[] | @base64')
for start in "${!dependencies[@]}"; do
  declare -A seen=()
  stack=( ${dependencies[$start]} )
  while ((${#stack[@]})); do
    node="${stack[-1]}"; unset 'stack[-1]'
    [[ "$node" == "$start" ]] && { echo "::error::Circular issue dependency includes #${start}"; exit 1; }
    [[ -n "${seen[$node]:-}" ]] && continue
    seen["$node"]=1
    [[ -n "${dependencies[$node]:-}" ]] && stack+=( ${dependencies[$node]} )
  done
done

macos_capacity_available() {
  local status run_id jobs all_jobs='[]'
  for status in in_progress queued pending waiting requested; do
    while IFS= read -r run_id; do
      [[ -z "$run_id" ]] && continue
      jobs=$(gh api --paginate "${api}/actions/runs/${run_id}/jobs?per_page=100" | jq -s 'map(.jobs // []) | add')
      all_jobs=$(jq --argjson page "$jobs" '. + $page' <<<"$all_jobs")
    done < <(gh api --paginate "${api}/actions/runs?status=${status}&per_page=100" --jq '.workflow_runs[]?.id')
  done
  ! jq -e 'any(.[]; (.status == "queued" or .status == "in_progress") and any(.labels[]?; . == "xcode-27" or . == "macos-latest" or (startswith("macos-"))))' <<<"$all_jobs" >/dev/null
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
sort_by([if any(.labels[]?.name; . == "priority-high") then 0 elif any(.labels[]?.name; . == "qa-failed") then 1 else 2 end, .createdAt, .number])[] | select(.author.login == "johnarleyburns")
| select(any(.labels[]?.name; . == "awaiting-ci-authorization" or . == "tracking" or . == "blocked-by-dependency" or . == "intake-running" or . == "intake-retry-deferred") | not)
| select((any(.labels[]?.name; . == "ready-for-qa") | not) or any(.labels[]?.name; . == "qa-failed"))
| select((any(.labels[]?.name; . == "needs-human-review") | not) or any(.labels[]?.name; . == "retry-ai"))
| select((any(.labels[]?.name; . == "intake-blocked") | not) or any(.labels[]?.name; . == "retry-ai")) | .number')
for issue in $issues; do
  qa_failed=$(gh issue view "$issue" --repo "$repo" --json labels --jq 'any(.labels[].name; . == "qa-failed")')
  [[ "$qa_failed" == true ]] || { grep -Fq "<!-- claude-issue:${issue} -->" <<<"$all_pr_bodies" && continue; }
  macos_capacity_available || exit 0
  attempt="$(date +%s)-${RANDOM}${RANDOM}"; marker="<!-- claude-intake-reservation issue=${issue} attempt=${attempt} -->"
  gh issue edit "$issue" --repo "$repo" --add-label intake-running --remove-label retry-ai >/dev/null
  reservation=$(printf '%s\n**Issue intake reservation:** controller-owned, awaiting dispatch confirmation.\n\nAttempt: `%s`' "$marker" "$attempt")
  comment_url=$(gh api --method POST "${api}/issues/${issue}/comments" -f body="$reservation" --jq '.url')
  response=$(gh api --method POST "${api}/actions/workflows/issue-to-pr.yml/dispatches" -f ref=main -f "inputs[issue_number]=${issue}" -f "inputs[attempt_id]=${attempt}" -f "inputs[base_sha]=${main_sha}" -F return_run_details=true 2>&1) || {
    gh issue edit "$issue" --repo "$repo" --add-label intake-blocked --add-label needs-human-review --remove-label intake-running >/dev/null || true
    gh api --method PATCH "$comment_url" -f body="$reservation

**Issue intake status:** dispatch outcome unknown. No automatic retry will occur; inspect this controller run, then apply `retry-ai` for one new attempt." >/dev/null || true
    echo "$response" >&2; exit 1; }
  run_id=$(jq -r '.workflow_run.id // .id // empty' <<<"$response")
  if [[ -z "$run_id" ]]; then
    # GitHub may accept dispatch with a 204/empty response despite the newer
    # response-detail contract. The attempt input plus durable reservation is
    # still sufficient for the worker to prove ownership. Do not remove the
    # reservation or falsely block the issue; finalization resolves it.
    gh api --method PATCH "$comment_url" -f body="$reservation

**Issue intake reservation:** GitHub accepted dispatch without returning a run ID. The generation-bound worker may proceed; this reservation remains the repository lock until it finalizes." >/dev/null
    echo "Dispatch accepted for #${issue} without run metadata; retaining attempt ${attempt}."; exit 0
  fi
  gh api --method PATCH "$comment_url" -f body="$reservation

**Issue intake reservation:** dispatched [workflow run ${run_id}](${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${run_id}). Only this attempt may allocate the macOS worker." >/dev/null
  echo "Admitted #${issue}, attempt ${attempt}, run ${run_id}; stopping after one."; exit 0
done
echo 'No eligible owner-authored issue requires admission.'
