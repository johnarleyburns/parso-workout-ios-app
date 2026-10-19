#!/usr/bin/env bash
# Convert every terminal issue-intake run into durable, queue-safe issue state.
# A PR failure can be repaired by PR automation; a pre-PR failure must never
# be retried blindly by the backlog sweep.
set -euo pipefail

repo="${GITHUB_REPOSITORY:?}"
issue="${ISSUE:?}"
result="${1:?implement job result required}"
run_url="${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${GITHUB_RUN_ID}"
marker='<!-- claude-intake-state -->'

ensure_label() {
  gh label create "$1" --repo "$repo" --color "$2" --description "$3" --force >/dev/null
}

ensure_label intake-running 1D76DB 'Issue implementation has been reserved or is running'
ensure_label intake-blocked D93F0B 'Pre-PR automation stopped; explicit owner retry or issue rework required'
ensure_label retry-ai FBCA04 'Owner-authorized retry of a blocked issue intake'

labels=$(gh issue view "$issue" --repo "$repo" --json labels --jq '[.labels[].name]')
has_label() { jq -e --arg label "$1" 'index($label) != null' <<<"$labels" >/dev/null; }

marker_comment_id() {
  gh api --paginate "repos/${repo}/issues/${issue}/comments?per_page=100" \
    --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | contains("<!-- claude-intake-state -->"))) | .id' \
    | tail -1
}

write_state() {
  local status="$1" detail="$2" id body
  body=$(printf '%s\n**Issue intake status:** %s\n\n%s\n\n[Workflow run](%s)' "$marker" "$status" "$detail" "$run_url")
  id=$(marker_comment_id || true)
  if [[ -n "$id" ]]; then
    gh api --method PATCH "repos/${repo}/issues/comments/${id}" -f body="$body" >/dev/null
  else
    gh issue comment "$issue" --repo "$repo" --body "$body" >/dev/null
  fi
}

# Preserve an already-published branch/PR and hand it to the existing PR
# reconciliation path. The intake result is not allowed to overwrite it.
marker_for_issue="<!-- claude-issue:${issue} -->"
prs=$(gh pr list --repo "$repo" --state all --base main --limit 200 --json number,state,body \
  | jq --arg marker "$marker_for_issue" '[.[] | select((.body // "") | contains($marker))]')
if jq -e 'any(.[]; .state == "OPEN" or .state == "MERGED")' <<<"$prs" >/dev/null; then
  clear_args=(--remove-label intake-running --remove-label intake-blocked --remove-label retry-ai)
  has_label intake-blocked && clear_args+=(--remove-label needs-human-review)
  gh issue edit "$issue" --repo "$repo" "${clear_args[@]}" >/dev/null 2>&1 || true
  write_state 'PR published' 'A linked PR exists or merged. PR/release reconciliation owns the remaining lifecycle.'
  exit 0
fi

# The implementation script has deliberately put CI-authorized work on hold;
# that is not a failed implementation and must remain resumable by its own
# authorization path.
if has_label awaiting-ci-authorization; then
  gh issue edit "$issue" --repo "$repo" --remove-label intake-running --remove-label retry-ai >/dev/null 2>&1 || true
  write_state 'waiting for owner authorization' 'This issue requires the owner-applied ai-ci-maintenance authorization label before implementation can continue.'
  exit 0
fi

if [[ "$result" == 'success' ]]; then
  gh issue edit "$issue" --repo "$repo" --remove-label intake-running --remove-label retry-ai >/dev/null 2>&1 || true
  write_state 'completed without a PR' 'The intake run completed as a valid no-op (for example, a closed issue). No retry was scheduled.'
  exit 0
fi

# Any failed intake without a PR is blocked. This includes no-diff agent exits,
# incomplete scope, validation exhaustion, cancellation, and setup failure.
# It is intentionally conservative: only an explicit owner retry can resume it.
gh issue edit "$issue" --repo "$repo" --add-label intake-blocked --add-label needs-human-review \
  --remove-label intake-running --remove-label ai-ready --remove-label retry-ai >/dev/null 2>&1 || true
write_state 'blocked before PR creation' "No branch or PR was safely published (implement job result: ${result}). The backlog will skip this issue. Review the run/artifacts, correct or split the issue if needed, then apply retry-ai to request one explicit new attempt."
