#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

plist_files=(
  "Cadence/Cadence/Info.plist"
  "Cadence/Cadence/PrivacyInfo.xcprivacy"
  "Cadence/Cadence Watch App Watch App/Cadence-Watch-App-Watch-App-Info.plist"
  "Cadence/Cadence Watch App Watch App/PrivacyInfo.xcprivacy"
  "CadenceWidgets/Info.plist"
  "CadenceWidgets/PrivacyInfo.xcprivacy"
)

for plist in "${plist_files[@]}"; do
  test -f "$plist" || { echo "release-safety: missing $plist" >&2; exit 1; }
  plutil -lint "$plist" >/dev/null
done

ios_info="Cadence/Cadence/Info.plist"
watch_info="Cadence/Cadence Watch App Watch App/Cadence-Watch-App-Watch-App-Info.plist"
privacy_files=(
  "Cadence/Cadence/PrivacyInfo.xcprivacy"
  "Cadence/Cadence Watch App Watch App/PrivacyInfo.xcprivacy"
  "CadenceWidgets/PrivacyInfo.xcprivacy"
)

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$ios_info")" = "Cladiron"
test "$(/usr/libexec/PlistBuddy -c 'Print :NSHealthShareUsageDescription' "$ios_info")" != ""
test "$(/usr/libexec/PlistBuddy -c 'Print :NSHealthUpdateUsageDescription' "$ios_info")" != ""
test "$(/usr/libexec/PlistBuddy -c 'Print :NSBluetoothAlwaysUsageDescription' "$ios_info")" != ""
test "$(/usr/libexec/PlistBuddy -c 'Print :NSLocationWhenInUseUsageDescription' "$ios_info")" != ""
test "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$ios_info")" = "false"
test "$(/usr/libexec/PlistBuddy -c 'Print :NSHealthShareUsageDescription' "$watch_info")" != ""
test "$(/usr/libexec/PlistBuddy -c 'Print :NSHealthUpdateUsageDescription' "$watch_info")" != ""

if /usr/libexec/PlistBuddy -c 'Print :NSMotionUsageDescription' "$ios_info" >/dev/null 2>&1; then
  echo "release-safety: unused Motion permission remains declared" >&2
  exit 1
fi

for privacy in "${privacy_files[@]}"; do
  /usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' "$privacy" >/dev/null
  /usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes' "$privacy" >/dev/null
done

if git ls-files | grep -E '(^|/)(\.env|.*\.(p8|p12|mobileprovision|pem|key|secret|token))$' >/dev/null; then
  echo "release-safety: credential-like file is tracked" >&2
  exit 1
fi

echo "release-safety: OK"
