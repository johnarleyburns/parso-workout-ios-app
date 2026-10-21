#!/usr/bin/env bash
# Record an accepted TestFlight upload against every GitHub issue associated with
# merged PRs contained in this binary. It never closes an issue. This runs *after* the
# upload command: an archive/export failure must never look delivered.
set -Eeuo pipefail

: "${APP_NAME:?set APP_NAME}"
: "${ARCHIVED_APP:?set ARCHIVED_APP to the .app inside the archive}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_SHA:?}"

repo=$GITHUB_REPOSITORY
sha=$GITHUB_SHA
run_url="${GITHUB_SERVER_URL:-https://github.com}/$repo/actions/runs/${GITHUB_RUN_ID:?}"
plist="$ARCHIVED_APP/Info.plist"
test -f "$plist"
bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
marker="<!-- testflight-delivery:${bundle}:${version}:${build} -->"
uploaded_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# A completed recorder step, rather than a merely-green workflow, is the
# durable signal that a preceding run actually uploaded a binary.  This keeps
# failed uploads in the range of the next accepted build.
previous=''
while IFS=$'\t' read -r id candidate; do
  [[ -n "$id" && "$id" != "${GITHUB_RUN_ID:-}" && "$candidate" != "$sha" ]] || continue
  if gh api --paginate "repos/$repo/actions/runs/$id/jobs" \
      --jq '.jobs[].steps[]? | select(.name == "Record TestFlight delivery" and .conclusion == "success") | .name' \
      | grep -qx 'Record TestFlight delivery'; then
    previous=$candidate
    break
  fi
done < <(gh run list --repo "$repo" --workflow ios.yml --branch main --limit 100 \
  --json databaseId,headSha,conclusion,event --jq '.[] | select((.event == "push" or .event == "workflow_dispatch") and .conclusion == "success") | [.databaseId, .headSha] | @tsv')

if [[ -n "$previous" ]]; then
  commits=$(gh api --paginate "repos/$repo/compare/$previous...$sha" --jq '.commits[].sha')
else
  # Initial traced upload: include only commits since the root that GitHub can
  # associate with a merged PR.  Already-delivered issues are filtered below.
  commits=$(git rev-list --reverse "$sha")
fi

trace_tmp=$(mktemp -d "${RUNNER_TEMP:-/tmp}/testflight-trace.XXXXXX")
trap 'rm -rf "$trace_tmp"' EXIT
prs_file="$trace_tmp/prs"
issues_file="$trace_tmp/issues"
while IFS= read -r commit; do
  [[ -n "$commit" ]] || continue
  while IFS= read -r pr; do [[ -n "$pr" ]] && printf '%s\n' "$pr" >> "$prs_file"; done < <(
    gh api "repos/$repo/commits/$commit/pulls" --jq \
      '.[] | select(.merged_at != null and .base.ref == "main") | .number')
done <<< "$commits"
sort -nu "$prs_file" -o "$prs_file" 2>/dev/null || : > "$prs_file"

while IFS= read -r pr; do
  [[ -n "$pr" ]] || continue
  # closingIssuesReferences is GitHub's PR-to-issue association.  Do not infer
  # issues from commit subjects; that loses squash and multi-issue PRs.
  query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){closingIssuesReferences(first:100){nodes{number title}}}}}'
  owner=${repo%%/*}; name=${repo#*/}
  while IFS=$'\t' read -r issue title; do
    [[ -n "$issue" ]] || continue
    printf '%s\t%s\n' "$issue" "$title" >> "$issues_file"
  done < <(gh api graphql -f query="$query" -F owner="$owner" -F name="$name" -F number="$pr" \
    --jq '.data.repository.pullRequest.closingIssuesReferences.nodes[] | [.number, .title] | @tsv')
  # Older generated PRs used this durable marker but did not include a GitHub
  # closing keyword.  Retain it as a fallback so an accepted build reaches the
  # originating issue without changing the issue's open/closed state.
  marker_issue=$(gh api "repos/$repo/pulls/$pr" --jq '.body // ""' \
    | sed -n 's/.*<!-- claude-issue:\([0-9][0-9]*\) -->.*/\1/p' | head -1)
  [[ -z "$marker_issue" ]] || printf '%s\t%s\n' "$marker_issue" 'Claude-generated issue' >> "$issues_file"
done < "$prs_file"
sort -t $'\t' -k1,1n -u "$issues_file" -o "$issues_file" 2>/dev/null || : > "$issues_file"
issue_count=$(wc -l < "$issues_file" | tr -d ' ')
prs_text=$(awk '{printf "#%s ", $1}' "$prs_file")

notes="$RUNNER_TEMP/testflight-notes-${build}.txt"
{
  printf '%s — %s (%s)\n\nIncluded fixes:\n' "$APP_NAME" "$version" "$build"
  while IFS=$'\t' read -r issue title; do
    [[ -n "$issue" ]] && printf -- '- #%s — %s\n' "$issue" "$title"
  done < "$issues_file"
  [[ "$issue_count" -gt 0 ]] || printf '%s\n' '- No GitHub issues were associated with the merged commits.'
  printf '\nGit commit: %s\n' "$sha"
} > "$notes"
head -c 4000 "$notes" > "$notes.limited" && mv "$notes.limited" "$notes"
cat "$notes" >> "$GITHUB_STEP_SUMMARY"

# Apple frequently accepts an upload before the build is indexed.  The separate
# scheduled reconciler performs retried, diagnosable App Store Connect checks.
availability='Upload accepted. Apple processing and tester distribution will be reconciled separately.'

while IFS=$'\t' read -r issue _title; do
  [[ -n "$issue" ]] || continue
  # Do not re-label or duplicate a historical record on a rerun of this build.
  existing=$(gh api --paginate "repos/$repo/issues/$issue/comments" --jq \
    ".[] | select(.body | contains(\"$marker\")) | .id" | head -1 || true)
  body="$marker
## TestFlight upload accepted

- App: **$APP_NAME** (\`$bundle\`)
- Version/build: **$version ($build)**
- Included by PR(s): $prs_text
- Commit: \`$sha\`
- Uploaded: $uploaded_at
- Status: **$availability**
- [Deployment workflow]($run_url)"
  if [[ -n "$existing" ]]; then
    gh api --method PATCH "repos/$repo/issues/comments/$existing" -f body="$body" >/dev/null
  else
    gh issue comment "$issue" --repo "$repo" --body "$body" >/dev/null
  fi
  gh label create testflight-uploaded --repo "$repo" --color 1D76DB \
    --description 'TestFlight upload was accepted; Apple processing is being reconciled.' --force >/dev/null
  gh label create testflight-processing --repo "$repo" --color FBCA04 \
    --description 'Apple is still processing the accepted TestFlight build.' --force >/dev/null
  gh issue edit "$issue" --repo "$repo" --add-label testflight-uploaded --add-label testflight-processing \
    --remove-label ready-for-qa --remove-label qa-failed >/dev/null
done < "$issues_file"

echo "Recorded TestFlight upload $bundle $version ($build) for $issue_count associated issue(s)."
