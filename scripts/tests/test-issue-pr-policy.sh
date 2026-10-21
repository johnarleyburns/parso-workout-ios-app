#!/usr/bin/env bash
# Exercise PR creation with a fake GitHub CLI; no network or repository writes.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/.github/scripts/issue-to-pr.sh"
trace=$(mktemp)
trap 'rm -f "$trace"' EXIT
eval "$(sed -n '/^make_pr() {/,/^}/p' "$root/.github/scripts/issue-to-pr.sh")"
title='Policy regression'
marker='<!-- claude-issue:1 -->'
ISSUE=1
api_failure=false
gh() {
  printf '%q ' "$@" >> "$trace"
  printf '\n' >> "$trace"
  case "$1 $2" in
    'pr create')
      [[ " $* " != *' --draft '* ]]
      printf '%s\n' 'https://github.com/example/repo/pull/123'
      ;;
    'pr view') printf '%s\n' '{"number":123,"id":"PR_123"}' ;;
    'api graphql')
      [[ "$*" == *'enablePullRequestAutoMerge'* && "$*" == *'id=PR_123'* ]]
      [[ "$api_failure" == false ]]
      ;;
    *) echo "Unexpected GitHub command: $*" >&2; return 1 ;;
  esac
}
number=$(make_pr example-branch)
[[ "$number" == 123 ]]
[[ $(wc -l < "$trace") -eq 3 ]]
! grep -Eqi '(^|[^[:alpha:]])(close[sd]?|fix(e[sd])?|resolve[sd]?):? #[0-9]+' "$trace"
grep -q 'human verification is required' "$trace"
! grep -q -- '--draft' "$trace"
grep -q 'enablePullRequestAutoMerge' "$trace"
# A failed auto-merge request must retain the created PR for reconciliation.
: > "$trace"
api_failure=true
number=$(make_pr example-branch 2>/dev/null)
[[ "$number" == 123 ]]
[[ $(grep -c '^pr create ' "$trace") -eq 1 ]]
echo 'PR creation policy: ready, explicit auto-merge'
# A failed local validation must never leave a branch or PR behind.
validate_line=$(grep -nF 'if validate "$attempt"' "$script" | cut -d: -f1)
publish_line=$(grep -nFx 'publish_changes' "$script" | cut -d: -f1)
pr_line=$(grep -nE '^pr_number=\$\(make_pr' "$script" | cut -d: -f1)
[[ "$validate_line" -lt "$publish_line" && "$publish_line" -lt "$pr_line" ]]
grep -Fq 'Pre-publication validation failed; no branch or PR was created' "$script"

# A human QA failure is an explicit repair request, even when an earlier PR
# merged. It must start a new branch and not be overwritten by reconciliation.
grep -Fq 'qa_failed=$(gh issue view "$ISSUE" --json labels' "$script"
grep -Fq 'Issue $ISSUE failed human QA: starting a repair cycle' "$script"
grep -Fq 'if [[ "$qa_failed" != true ]]; then' "$script"
grep -Fq 'github.event.label.name == '\''qa-failed'\''' "$root/.github/workflows/issue-backlog-reconcile.yml"
grep -Fq 'or any(.labels[]?.name; . == "qa-failed")' "$root/.github/scripts/admit-one-stranded-issue.sh"
grep -Fq -- '--remove-label qa-failed' "$root/.github/scripts/record-testflight-delivery.sh"
grep -Fq 'human QA failure is awaiting repair' "$root/.github/scripts/reconcile-testflight-status.sh"
echo 'QA failure policy: repair supersedes prior ready/merged state'

# Source filenames may describe credentials without being credential artifacts;
# binary/config artifacts and non-source secret files remain blocked.
for guarded in "$script" "$root/.github/scripts/pr-conflict-repair.sh" "$root/.github/scripts/release-repair.sh"; do
  policy=$(sed -n '/^is_sensitive_path() {/,/^}/p' "$guarded")
  eval "$policy"
  ! is_sensitive_path 'Sources/Features/Settings/JamendoCredentialView.swift'
  is_sensitive_path 'Config/credentials.json'
  is_sensitive_path 'certs/distribution.p12'
  is_sensitive_path 'fastlane/Appfile'
done
echo 'Sensitive-path policy: Swift credential views allowed; deployment artifacts blocked'

tmp=$(mktemp -d)
trap 'rm -f "$trace"; rm -rf "$tmp"' EXIT
(
  cd "$tmp"
  git init -q
  git config user.email test@example.invalid
  git config user.name test
  printf 'baseline\n' > CredentialView.swift
  git add CredentialView.swift && git commit -qm baseline
  printf 'let token = "ghp_abcdefghijklmnopqrstuvwxyz123456"\n' > CredentialView.swift
  git add CredentialView.swift
  eval "$(sed -n '/^contains_secret_material() {/,/^}/p' "$script")"
  contains_secret_material CredentialView.swift
)
echo 'Sensitive-content policy: token-like additions rejected in allowed source paths'
