#!/usr/bin/env bash
# The Watch app's icon is the watchOS circle (Icon Composer's 1088 canvas) of the
# shared Icon Composer file Cadence/Cadence/AppIcon.icon. The Watch target gets it
# through a synchronized-folder membership exception on the "Cadence" folder, and
# must not carry its own AppIcon.appiconset (two icons named AppIcon clash).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON="$ROOT/Cadence/Cadence/AppIcon.icon"
LEGACY_SET="$ROOT/Cadence/Cadence Watch App Watch App/Assets.xcassets/AppIcon.appiconset"
PROJECT="$ROOT/Cadence/Cadence.xcodeproj"
WATCH_TARGET="Cadence Watch App Watch App"

fail() {
  echo "watch-appicon: $*" >&2
  exit 1
}

[[ -f "$ICON/icon.json" ]] || fail "missing $ICON/icon.json (edit the icon in Icon Composer)"
[[ ! -e "$LEGACY_SET" ]] \
  || fail "remove $LEGACY_SET; the Watch icon comes from AppIcon.icon"
[[ -f "$PROJECT/project.pbxproj" ]] || fail "missing Xcode project"

python3 - "$ICON/icon.json" "$PROJECT/project.pbxproj" "$WATCH_TARGET" <<'PY' || exit 1
import json, re, sys
icon_json, pbxproj, watch_target = sys.argv[1:]
circles = json.load(open(icon_json)).get("supported-platforms", {}).get("circles", [])
if "watchOS" not in circles:
    sys.exit("watch-appicon: AppIcon.icon does not declare the watchOS circle; enable watchOS in Icon Composer")
project = open(pbxproj).read()
pattern = (r'Exceptions for "Cadence" folder in "' + re.escape(watch_target) + r'" target \*/ = \{'
           r'[^}]*membershipExceptions = \([^)]*AppIcon\.icon,')
if not re.search(pattern, project):
    sys.exit("watch-appicon: AppIcon.icon is not a member of the Watch target "
             "(tick the Watch target under Target Membership for Cadence/AppIcon.icon)")
PY

if ! command -v xcodebuild >/dev/null 2>&1; then
  fail "xcodebuild is required to verify the Watch target settings"
fi

settings="$(xcodebuild -project "$PROJECT" -target "$WATCH_TARGET" -showBuildSettings 2>/dev/null)" \
  || fail "could not read Watch target build settings"
grep -Fq 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon' <<<"$settings" \
  || fail "Watch target is not configured to compile AppIcon"
grep -Fq 'SDKROOT = ' <<<"$settings" \
  || fail "Watch target build settings did not expose SDKROOT"
grep -Fq '/Platforms/WatchOS.platform/Developer/SDKs/' <<<"$settings" \
  || fail "Watch target does not resolve to the watchOS SDK"

# A missing watchOS runtime icon builds silently and only fails at upload, so
# compile the .icon with watchOS actool and require CFBundleIconName.
out="$(mktemp -d "${TMPDIR:-/tmp}/cladiron-watch-icon.XXXXXX")"
trap 'rm -rf "$out"' EXIT
xcrun actool "$ICON" --compile "$out" --platform watchos --target-device watch \
  --minimum-deployment-target 10.0 --app-icon AppIcon \
  --output-partial-info-plist "$out/info.plist" --output-format human-readable-text \
  --errors --warnings >/dev/null 2>&1 \
  || fail "watchOS actool rejected AppIcon.icon"
icon_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' "$out/info.plist" 2>/dev/null || true)"
[[ "$icon_name" == "AppIcon" ]] \
  || fail "watchOS actool did not produce CFBundleIconName=AppIcon from AppIcon.icon"

echo "watch-appicon: valid watchOS AppIcon (AppIcon.icon watchOS circle, CFBundleIconName=AppIcon)"
