#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

test -s "docs/app-store/featuring-nomination.md"
test -s "docs/press/press-kit.md"
if rg -n "private iCloud|iCloud backup|automatic iCloud|syncs back|everything syncs|Motion data" docs/app-store/metadata.md >/dev/null; then
  echo "release-safety: store copy overclaims cloud sync or declares unused Motion data" >&2
  exit 1
fi

# App Review 5.1.3(ii): no personal health information in iCloud. The shipping
# build is local-only, so no iCloud entitlement or CloudKit code may remain.
#
# `CLOUDKIT_RECOVERY_BUILD` is a one-off exception for the 1184 data-recovery
# build: it restores the iCloud entitlement and a read-only import path so the
# user can pull their pre-1184 history out of the existing private container.
# It must be removed before the next App Store submission.
if [ -e "CLOUDKIT_RECOVERY_BUILD" ]; then
  echo "release-safety: CLOUDKIT_RECOVERY_BUILD is present; skipping the local-only assertions" >&2
else
if rg -n "iCloud|CloudKit|CKContainer|NSPersistentCloudKitContainer|cloudKitDatabase|cloudKitEnabled" Cadence/Cadence --glob '*.swift' >/dev/null; then
  echo "release-safety: iCloud/CloudKit code remains in the app target" >&2
  exit 1
fi
test ! -e "Cadence/Cadence/Features/Settings/CloudKitSyncDiagnosticsView.swift" || {
  echo "release-safety: CloudKit diagnostics screen remains" >&2
  exit 1
}
for ent in "Cadence/Cadence/Cadence.entitlements" \
           "Cadence/Cadence/Cadence.Release.entitlements" \
           "Cadence/Cadence/Cadence.Debug.entitlements"; do
  test -f "$ent" || { echo "release-safety: missing $ent" >&2; exit 1; }
  if grep -q "com.apple.developer.icloud" "$ent"; then
    echo "release-safety: iCloud entitlement remains in $ent" >&2
    exit 1
  fi
done
fi

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
test "$(/usr/libexec/PlistBuddy -c 'Print :NSLocationAlwaysAndWhenInUseUsageDescription' "$ios_info")" != ""
if /usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes' "$ios_info" | grep -q "remote-notification"; then
  echo "release-safety: unused remote-notification background mode remains declared" >&2
  exit 1
fi
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

# Required-reason APIs actually used by the shipping code.
phone_privacy="Cadence/Cadence/PrivacyInfo.xcprivacy"
watch_privacy="Cadence/Cadence Watch App Watch App/PrivacyInfo.xcprivacy"
grep -q "NSPrivacyAccessedAPICategoryUserDefaults" "$phone_privacy" || { echo "release-safety: phone UserDefaults reason missing" >&2; exit 1; }
grep -q "NSPrivacyAccessedAPICategoryFileTimestamp" "$phone_privacy" || { echo "release-safety: phone FileTimestamp reason missing" >&2; exit 1; }
grep -q "3B52.1" "$phone_privacy" || { echo "release-safety: phone FileTimestamp reason code missing" >&2; exit 1; }
grep -q "NSPrivacyAccessedAPICategoryUserDefaults" "$watch_privacy" || { echo "release-safety: watch UserDefaults reason missing" >&2; exit 1; }
grep -q "NSPrivacyAccessedAPICategorySystemBootTime" "$watch_privacy" || { echo "release-safety: watch SystemBootTime reason missing" >&2; exit 1; }
grep -q "35F9.1" "$watch_privacy" || { echo "release-safety: watch SystemBootTime reason code missing" >&2; exit 1; }

if git ls-files | grep -E '(^|/)(\.env|.*\.(p8|p12|mobileprovision|pem|key|secret|token))$' >/dev/null; then
  echo "release-safety: credential-like file is tracked" >&2
  exit 1
fi

echo "release-safety: OK"
