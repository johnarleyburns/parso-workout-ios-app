#!/usr/bin/env bash
# Emits `skip=true` when the exact tree being built on main already passed the
# full pull-request gate, so the post-merge release does not repeat the same
# suite on an identical tree.
#
# Invariants (all must hold, otherwise we fall back to running the tests):
#   1. the event is a push to main, not a manual dispatch;
#   2. the commit is the merge commit of a merged pull request;
#   3. that pull request's head tree is byte-identical to this commit's tree
#      (true for a squash merge that was up to date at merge time);
#   4. the required `host-tests` and `app-build` check runs on that exact pull
#      request head SHA completed successfully.
#
# The script never fails the job: any error or ambiguity prints `skip=false`.
set -euo pipefail

emit() { printf 'skip=%s\n' "$1"; }
# Fail closed: unknown state means "run the tests".
trap 'emit false; exit 0' ERR

if [[ "${GITHUB_EVENT_NAME:-}" != "push" ]]; then emit false; exit 0; fi
if [[ "${GITHUB_REF:-}" != "refs/heads/main" ]]; then emit false; exit 0; fi
if [[ "${FORCE_TESTS:-0}" == "1" ]]; then emit false; exit 0; fi
: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}"

tree=$(git rev-parse HEAD^{tree})
pr=$(gh api "repos/$GITHUB_REPOSITORY/commits/$GITHUB_SHA/pulls" --jq '.[0].number // empty')
if [[ -z "$pr" ]]; then emit false; exit 0; fi

pull=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$pr")
merged_at=$(jq -r '.merged_at // empty' <<<"$pull")
merge_sha=$(jq -r '.merge_commit_sha // empty' <<<"$pull")
head_sha=$(jq -r '.head.sha // empty' <<<"$pull")
if [[ -z "$merged_at" || "$merge_sha" != "$GITHUB_SHA" || -z "$head_sha" ]]; then
  emit false; exit 0
fi

if ! git cat-file -e "$head_sha^{commit}" 2>/dev/null; then
  git fetch --no-tags --depth=1 origin "$head_sha" >/dev/null 2>&1 || { emit false; exit 0; }
fi
head_tree=$(git rev-parse "$head_sha^{tree}" 2>/dev/null) || { emit false; exit 0; }
if [[ "$head_tree" != "$tree" ]]; then emit false; exit 0; fi

checks=$(gh api "repos/$GITHUB_REPOSITORY/commits/$head_sha/check-runs?per_page=100")
both_passed=$(jq -r '
  [ (.check_runs // [])[]
    | select((.name == "host-tests" or .name == "app-build")
             and .status == "completed"
             and .conclusion == "success") ]
  | (any(.[]; .name == "host-tests") and any(.[]; .name == "app-build"))
' <<<"$checks")

if [[ "$both_passed" == "true" ]]; then
  echo "Tree $tree already passed host-tests and app-build on PR #$pr ($head_sha)" >&2
  emit true
else
  echo "PR #$pr did not report a successful host-tests and app-build for $head_sha" >&2
  emit false
fi
