#!/usr/bin/env bash
# Record an accepted TestFlight upload against every GitHub issue closed by the
# merged PRs contained in this binary.  This deliberately runs *after* the
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
  --json databaseId,headSha,conclusion,event --jq '.[] | select(.event == "push" and .conclusion == "success") | [.databaseId, .headSha] | @tsv')

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

# App Store Connect does not promise that an accepted upload is immediately
# visible.  When the workflow supplies its API key, make a best-effort update
# of "What to Test" only after the build is processing-complete.  A later
# deployment reruns this harmlessly if Apple is still processing it now.
availability='Uploaded to App Store Connect; Apple processing and tester-group availability are not yet confirmed.'
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" && -f "${ASC_KEY_PATH:-}" ]]; then
  token=$(ruby -rjson -ropenssl -rbase64 -e '
    h=Base64.urlsafe_encode64({alg:"ES256",kid:ENV.fetch("ASC_KEY_ID"),typ:"JWT"}.to_json,padding:false)
    p=Base64.urlsafe_encode64({iss:ENV.fetch("ASC_ISSUER_ID"),aud:"appstoreconnect-v1",exp:Time.now.to_i+600}.to_json,padding:false)
    key=OpenSSL::PKey.read(File.read(ENV.fetch("ASC_KEY_PATH")))
    s=Base64.urlsafe_encode64(key.sign("SHA256", "#{h}.#{p}"),padding:false); print "#{h}.#{p}.#{s}"')
  auth=(-H "Authorization: Bearer $token" -H 'Content-Type: application/json')
  app_json=$(curl -fsS "${auth[@]}" --get --data-urlencode "filter[bundleId]=$bundle" \
    'https://api.appstoreconnect.apple.com/v1/apps' 2>/dev/null || true)
  app_id=$(printf '%s' "$app_json" | ruby -rjson -e 'j=JSON.parse(STDIN.read) rescue {}; print j.dig("data",0,"id").to_s')
  build_json=''; build_id=''; state=''
  if [[ -n "$app_id" ]]; then
    build_json=$(curl -fsS "${auth[@]}" --get --data-urlencode "filter[app]=$app_id" --data-urlencode "filter[version]=$build" \
      'https://api.appstoreconnect.apple.com/v1/builds' 2>/dev/null || true)
    build_id=$(printf '%s' "$build_json" | ruby -rjson -e 'j=JSON.parse(STDIN.read) rescue {}; print j.dig("data",0,"id").to_s')
    state=$(printf '%s' "$build_json" | ruby -rjson -e 'j=JSON.parse(STDIN.read) rescue {}; print j.dig("data",0,"attributes","processingState").to_s')
  fi
  if [[ "$state" == VALID && -n "$build_id" ]]; then
    payload=$(NOTES="$notes" BUILD_ID="$build_id" ruby -rjson -e 'puts({data:{type:"betaBuildLocalizations",attributes:{locale:"en-US",whatsNew:File.read(ENV.fetch("NOTES"))},relationships:{build:{data:{type:"builds",id:ENV.fetch("BUILD_ID")}}}}}.to_json)')
    # 409 means the localization already exists from a rerun; that is safe.
    curl -sS -o /dev/null -w '%{http_code}' "${auth[@]}" -X POST --data "$payload" \
      'https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations' | grep -Eq '^(200|201|409)$' || true
    groups=$(curl -fsS "${auth[@]}" "https://api.appstoreconnect.apple.com/v1/builds/$build_id/betaGroups" 2>/dev/null || true)
    group_count=$(printf '%s' "$groups" | ruby -rjson -e 'j=JSON.parse(STDIN.read) rescue {}; print Array(j["data"]).length')
    if [[ "$group_count" =~ ^[1-9] ]]; then
      availability="Available to $group_count assigned TestFlight tester group(s)."
    else
      availability='Apple processing completed, but no assigned TestFlight tester group was reported.'
    fi
  fi
fi

while IFS=$'\t' read -r issue _title; do
  [[ -n "$issue" ]] || continue
  # Do not re-label or duplicate a historical record on a rerun of this build.
  existing=$(gh api --paginate "repos/$repo/issues/$issue/comments" --jq \
    ".[] | select(.body | contains(\"$marker\")) | .id" | head -1 || true)
  body="$marker
## TestFlight upload accepted

- App: **$APP_NAME** (`$bundle`)
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
  # New deployments wait for an actual assigned tester group.  Workout retains
  # its separate legacy upload-stage label temporarily for compatibility.
  if [[ "$availability" == Available\ to\ * ]]; then
    gh label create ready-for-qa --repo "$repo" --color 0E8A16 \
      --description 'Build is available to an assigned TestFlight tester group' --force >/dev/null
    gh issue edit "$issue" --repo "$repo" --add-label ready-for-qa >/dev/null
  fi
done < "$issues_file"

echo "Recorded TestFlight upload $bundle $version ($build) for $issue_count associated issue(s)."
