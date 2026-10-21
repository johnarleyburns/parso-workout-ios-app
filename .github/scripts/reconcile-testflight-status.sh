#!/usr/bin/env bash
# Reconcile the availability of accepted TestFlight uploads.  Upload acceptance,
# Apple processing, and tester-group membership are intentionally distinct facts.
# This script is safe to re-run: it updates one durable status comment per build.
set -Eeuo pipefail

: "${GITHUB_REPOSITORY:?}"
: "${GH_TOKEN:?}"
: "${ASC_KEY_ID:?}"
: "${ASC_ISSUER_ID:?}"
: "${ASC_KEY_PATH:?}"
test -f "$ASC_KEY_PATH" || { echo "::error::ASC key file is unavailable"; exit 1; }

repo=$GITHUB_REPOSITORY
only_issue=${1:-}
tmp=$(mktemp -d "${RUNNER_TEMP:-/tmp}/testflight-status.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

token=$(ruby -rjson -ropenssl -rbase64 -e '
  h=Base64.urlsafe_encode64({alg:"ES256",kid:ENV.fetch("ASC_KEY_ID"),typ:"JWT"}.to_json,padding:false)
  p=Base64.urlsafe_encode64({iss:ENV.fetch("ASC_ISSUER_ID"),aud:"appstoreconnect-v1",exp:Time.now.to_i+600}.to_json,padding:false)
  key=OpenSSL::PKey.read(File.read(ENV.fetch("ASC_KEY_PATH")))
  # OpenSSL returns ASN.1 DER ECDSA signatures; JWS ES256 requires raw,
  # fixed-width r||s (32 bytes each), not the DER sequence.
  der=key.sign("SHA256", "#{h}.#{p}")
  values=OpenSSL::ASN1.decode(der).value.map(&:value)
  raise "invalid ECDSA signature" unless values.length == 2
  raw=values.map { |n| [n.to_s(16).rjust(64,"0")].pack("H*") }.join
  raise "invalid ES256 signature length" unless raw.bytesize == 64
  s=Base64.urlsafe_encode64(raw,padding:false); print "#{h}.#{p}.#{s}"')
auth=(-H "Authorization: Bearer $token" -H 'Content-Type: application/json')

ensure_label() {
  gh label create "$1" --repo "$repo" --color "$2" --description "$3" --force >/dev/null
}
ensure_label testflight-uploaded '1D76DB' 'TestFlight upload was accepted; Apple processing is being reconciled.'
ensure_label testflight-processing 'FBCA04' 'Apple is still processing the accepted TestFlight build.'
ensure_label testflight-distribution-confirmed '5319E7' 'App Store Connect reports at least one assigned tester group.'
ensure_label testflight-access-unverified 'BFD4F2' 'Tester-group access was not verified automatically; the build may still be available.'
ensure_label ready-for-qa '0E8A16' 'Apple processing completed; the exact TestFlight build is ready for human QA.'

api_get() {
  local outfile=$1; shift
  HTTP_CODE=$(curl -sS -o "$outfile" -w '%{http_code}' "${auth[@]}" "$@") || return 1
}

# App Manager credentials can read a group's builds, while Apple rejects the
# inverse /builds/{id}/betaGroups relationship. Return a compatible one-item
# group response only when this exact build is in the required Internal QA
# group; traverse all pages so historical builds are handled correctly.
internal_qa_for_build() {
  local outfile=$1 app_id=$2 build_id=$3 qa_group_id group_url next_url
  api_get "$outfile" --get --data-urlencode "filter[app]=$app_id" --data-urlencode 'filter[name]=Internal QA' 'https://api.appstoreconnect.apple.com/v1/betaGroups'
  [[ "$HTTP_CODE" == 200 ]] || return 0
  qa_group_id=$(jq -r '.data[] | select(.attributes.name == "Internal QA") | .id' "$outfile" | head -1)
  if [[ -z "$qa_group_id" ]]; then printf '%s\n' '{"data":[]}' > "$outfile"; return 0; fi
  group_url="https://api.appstoreconnect.apple.com/v1/betaGroups/$qa_group_id/relationships/builds?limit=200"
  while [[ -n "$group_url" ]]; do
    api_get "$outfile" "$group_url"
    [[ "$HTTP_CODE" == 200 ]] || return 0
    if jq -e --arg build "$build_id" 'any(.data[]?; .id == $build)' "$outfile" >/dev/null; then
      jq -n --arg id "$qa_group_id" '{data:[{id:$id}]}' > "$outfile"
      HTTP_CODE=200
      return 0
    fi
    next_url=$(jq -r '.links.next // empty' "$outfile")
    group_url=$next_url
  done
  printf '%s\n' '{"data":[]}' > "$outfile"
  HTTP_CODE=200
}

reconcile_issue() {
  local issue=$1 marker bundle version build status_marker comments delivery body app_id build_id state groups_count availability detail existing
  comments="$tmp/comments-$issue"
  gh api --paginate "repos/$repo/issues/$issue/comments" --jq '.[].body' > "$comments" || return 0
  # Human QA failure takes precedence over the prior build's availability. A
  # replacement build clears qa-failed in record-testflight-delivery.sh.
  if gh issue view "$issue" --repo "$repo" --json labels --jq '.labels[].name' | grep -Fxq 'qa-failed'; then
    gh issue edit "$issue" --repo "$repo" --remove-label ready-for-qa --remove-label ai-ready >/dev/null
    echo "Reconciled #$issue: human QA failure is awaiting repair"
    return 0
  fi
  delivery=$(rg '<!-- testflight-delivery:[^:]+:[^:]+:[^ ]+ -->' "$comments" | tail -1 || true)
  if [[ -z "$delivery" ]]; then
    # Historical upload-stage labels have no exact build to verify.  Do not
    # preserve a claim of QA readiness that App Store Connect cannot support.
    gh issue edit "$issue" --repo "$repo" --remove-label ready-for-qa --remove-label testflight-uploaded --remove-label testflight-processing --remove-label testflight-distribution-confirmed --remove-label testflight-access-unverified >/dev/null
    echo "Reconciled #$issue: no traceable TestFlight build"
    return 0
  fi
  marker=$delivery
  bundle=$(sed -E 's/^<!-- testflight-delivery:([^:]+):.*$/\1/' <<<"$marker")
  version=$(sed -E 's/^<!-- testflight-delivery:[^:]+:([^:]+):.*$/\1/' <<<"$marker")
  build=$(sed -E 's/^<!-- testflight-delivery:[^:]+:[^:]+:([^ ]+) -->$/\1/' <<<"$marker")
  status_marker="<!-- testflight-status:${bundle}:${version}:${build} -->"
  body="$tmp/body-$issue"

  if ! api_get "$body" --get --data-urlencode "filter[bundleId]=$bundle" 'https://api.appstoreconnect.apple.com/v1/apps'; then
    echo "::error::App Store Connect transport failure; preserving existing TestFlight labels for #$issue" >&2
    return 1
  fi
  if [[ "$HTTP_CODE" != 200 ]]; then
    status='Upload accepted; App Store Connect lookup could not be verified yet.'
    detail="App Store Connect app lookup returned HTTP $HTTP_CODE. The scheduled reconciler will retry; this is not evidence that the build is unavailable."
    gh issue edit "$issue" --repo "$repo" --add-label testflight-uploaded --add-label testflight-access-unverified --remove-label testflight-processing --remove-label testflight-distribution-confirmed --remove-label ready-for-qa >/dev/null
  else
    app_id=$(jq -r '.data[0].id // empty' "$body")
    if [[ -z "$app_id" ]]; then
      status='Upload accepted; the build is not indexed by App Store Connect yet.'
      detail='Apple has not exposed the app record to this lookup yet. The scheduled reconciler will retry.'
      gh issue edit "$issue" --repo "$repo" --add-label testflight-uploaded --add-label testflight-processing --remove-label testflight-distribution-confirmed --remove-label ready-for-qa --remove-label testflight-access-unverified >/dev/null
    else
      api_get "$body" --get --data-urlencode "filter[app]=$app_id" --data-urlencode "filter[version]=$build" 'https://api.appstoreconnect.apple.com/v1/builds'
      if [[ "$HTTP_CODE" != 200 ]]; then
        status='Upload accepted; App Store Connect build lookup could not be verified yet.'
        detail="App Store Connect build lookup returned HTTP $HTTP_CODE. The scheduled reconciler will retry; this is not evidence that the build is unavailable."
        gh issue edit "$issue" --repo "$repo" --add-label testflight-uploaded --add-label testflight-access-unverified --remove-label testflight-processing --remove-label testflight-distribution-confirmed --remove-label ready-for-qa >/dev/null
      else
        build_id=$(jq -r '.data[0].id // empty' "$body")
        state=$(jq -r '.data[0].attributes.processingState // empty' "$body")
        if [[ "$state" != VALID || -z "$build_id" ]]; then
          status='Upload accepted; Apple is still processing this build.'
          detail="App Store Connect processing state: ${state:-not indexed}. The scheduled reconciler will retry."
          gh issue edit "$issue" --repo "$repo" --add-label testflight-uploaded --add-label testflight-processing --remove-label testflight-distribution-confirmed --remove-label ready-for-qa --remove-label testflight-access-unverified >/dev/null
        else
          internal_qa_for_build "$body" "$app_id" "$build_id"
          if [[ "$HTTP_CODE" == 200 ]]; then
            groups_count=$(jq '.data | length' "$body")
            if [[ "$groups_count" -gt 0 ]]; then
              status='Apple processing completed; tester-group distribution is confirmed.'
              detail="App Store Connect reports $groups_count assigned tester group(s)."
              gh issue edit "$issue" --repo "$repo" --add-label testflight-uploaded --add-label testflight-distribution-confirmed --add-label ready-for-qa --remove-label testflight-processing --remove-label testflight-access-unverified >/dev/null
            else
              status='Apple processing completed; tester-group membership was not reported.'
              detail='The build is ready for human QA. Group reporting is separate observability and does not block QA readiness.'
              gh issue edit "$issue" --repo "$repo" --add-label testflight-uploaded --add-label ready-for-qa --add-label testflight-access-unverified --remove-label testflight-processing --remove-label testflight-distribution-confirmed >/dev/null
            fi
          else
            status='Apple processing completed; tester-group access could not be verified.'
            detail="The build is ready for human QA. App Store Connect beta-group lookup returned HTTP $HTTP_CODE; the reconciler will retry."
            gh issue edit "$issue" --repo "$repo" --add-label testflight-uploaded --add-label ready-for-qa --add-label testflight-access-unverified --remove-label testflight-processing --remove-label testflight-distribution-confirmed >/dev/null
          fi
        fi
      fi
    fi
  fi

  existing=$(gh api --paginate "repos/$repo/issues/$issue/comments" --jq ".[] | select(.body | contains(\"$status_marker\")) | .id" | head -1 || true)
  availability="$status_marker
## TestFlight availability

- App: **$bundle**
- Version/build: **$version ($build)**
- Status: **$status**
- Detail: $detail
- Reconciled: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -n "$existing" ]]; then
    gh api --method PATCH "repos/$repo/issues/comments/$existing" -f body="$availability" >/dev/null
  else
    gh issue comment "$issue" --repo "$repo" --body "$availability" >/dev/null
  fi
  echo "Reconciled #$issue: $status"
}

if [[ -n "$only_issue" ]]; then
  reconcile_issue "$only_issue"
else
  while IFS= read -r issue; do reconcile_issue "$issue"; done < <(gh issue list --repo "$repo" --state open --limit 1000 --json number --jq '.[].number')
fi
