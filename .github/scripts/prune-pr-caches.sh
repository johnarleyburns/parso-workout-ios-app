#!/usr/bin/env bash
# Reclaim the repository Actions cache budget.
#
# Pull-request caches are only restorable by the pull request that wrote them
# (GitHub resolves restore keys against the current ref and the default branch),
# so once a PR closes they are dead weight. They also crowd out the default
# branch seeds that every PR depends on. This script deletes closed-PR caches
# and, if the budget is still over the soft limit, the oldest remaining
# non-default-branch entries.
#
# Idempotent and safe to run on a schedule. Exits non-zero only when the cache
# API itself is unavailable.
set -euo pipefail

repo="${GITHUB_REPOSITORY:?}"
soft_limit_bytes=$((8 * 1024 * 1024 * 1024))

listing=$(gh api "repos/$repo/actions/caches?per_page=100" --paginate \
  --jq '.actions_caches[] | [.id, .ref, .size_in_bytes] | @tsv')

total=0
declare -a candidates=()

while IFS=$'\t' read -r id ref size; do
  [[ -n "${id:-}" ]] || continue
  total=$((total + size))
  [[ "$ref" == refs/pull/* ]] || continue
  number="${ref#refs/pull/}"
  number="${number%/merge}"
  [[ "$number" =~ ^[0-9]+$ ]] || continue

  state=$(gh api "repos/$repo/pulls/$number" --jq '.state' 2>/dev/null || echo unknown)
  if [[ "$state" == "closed" ]]; then
    echo "Deleting cache $id for closed PR #$number (${size} bytes)"
    gh api -X DELETE "repos/$repo/actions/caches/$id" >/dev/null
    total=$((total - size))
  else
    candidates+=("$size"$'\t'"$id"$'\t'"$ref")
  fi
done <<<"$listing"

# Cache ids increase monotonically, so the smallest id is the oldest entry.
while (( total > soft_limit_bytes )) && (( ${#candidates[@]} > 0 )); do
  oldest=$(printf '%s\n' "${candidates[@]}" | sort -n -t$'\t' -k2,2 | head -n 1)
  IFS=$'\t' read -r size id ref <<<"$oldest"
  echo "Deleting oldest pull-request cache $id ($ref, ${size} bytes) to stay under budget"
  gh api -X DELETE "repos/$repo/actions/caches/$id" >/dev/null
  total=$((total - size))
  remaining=()
  for entry in "${candidates[@]}"; do
    [[ "$entry" == "$oldest" ]] || remaining+=("$entry")
  done
  candidates=("${remaining[@]+"${remaining[@]}"}")
done

echo "Actions cache usage after pruning: $((total / 1024 / 1024)) MiB"
