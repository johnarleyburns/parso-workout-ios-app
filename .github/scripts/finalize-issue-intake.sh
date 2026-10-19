#!/usr/bin/env bash
# Finalize only the matching controller reservation; stale runs cannot alter a
# newer attempt's labels or retry state.
set -euo pipefail
repo="${GITHUB_REPOSITORY:?}"; issue="${ISSUE:?}"; result="${1:?}"; attempt="${2:?}"
marker="<!-- claude-intake-reservation issue=${issue} attempt=${attempt} -->"
run_url="${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${GITHUB_RUN_ID}"
ensure_label() { gh label create "$1" --repo "$repo" --color "$2" --description "$3" --force >/dev/null; }
ensure_label intake-blocked D93F0B 'Pre-PR automation stopped; explicit owner retry or issue rework required'
ensure_label retry-ai FBCA04 'Owner-authorized retry request; handled by the intake controller'
reservation=$(gh api --paginate "repos/${repo}/issues/${issue}/comments?per_page=100" --jq ".[] | select(.body | contains(\"${marker}\")) | .body" | tail -1)
[[ -n "$reservation" ]] || { echo "Stale attempt ${attempt}; state untouched."; exit 0; }
marker_for_issue="<!-- claude-issue:${issue} -->"
prs=$(gh pr list --repo "$repo" --state all --base main --limit 1000 --json number,state,body | jq --arg marker "$marker_for_issue" '[.[] | select((.body // "") | contains($marker))]')
if jq -e 'any(.[]; .state == "OPEN" or .state == "MERGED")' <<<"$prs" >/dev/null; then
  gh issue edit "$issue" --repo "$repo" --remove-label intake-running --remove-label intake-blocked --remove-label retry-ai >/dev/null || true; exit 0
fi
state=$(gh issue view "$issue" --repo "$repo" --json state --jq .state)
if [[ "$result" == success && "$state" == CLOSED ]]; then gh issue edit "$issue" --repo "$repo" --remove-label intake-running --remove-label retry-ai >/dev/null || true; exit 0; fi
gh issue edit "$issue" --repo "$repo" --add-label intake-blocked --add-label needs-human-review --remove-label intake-running --remove-label ai-ready --remove-label retry-ai >/dev/null || true
body=$(printf '%s\n**Issue intake status:** blocked before PR creation.\n\nAttempt `%s` ended as `%s` without a linked PR. Review [the implementation run](%s), correct the issue or split its scope, then apply `retry-ai` for one controller-mediated retry.' "<!-- claude-intake-state attempt=${attempt} -->" "$attempt" "$result" "$run_url")
gh issue comment "$issue" --repo "$repo" --body "$body" >/dev/null
