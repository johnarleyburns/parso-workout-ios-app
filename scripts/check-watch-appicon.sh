#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_DIR="$ROOT/Cadence/Cadence Watch App Watch App/Assets.xcassets/AppIcon.appiconset"
CONTENTS="$ICON_DIR/Contents.json"
PROJECT="$ROOT/Cadence/Cadence.xcodeproj"
WATCH_TARGET="Cadence Watch App Watch App"

fail() {
  echo "watch-appicon: $*" >&2
  exit 1
}

[[ -f "$CONTENTS" ]] || fail "missing $CONTENTS"
[[ -f "$PROJECT/project.pbxproj" ]] || fail "missing Xcode project"

extract() {
  /usr/bin/plutil -extract "$1" raw -o - "$CONTENTS"
}

filename="$(extract images.0.filename 2>/dev/null)" \
  || fail "the first AppIcon image has no filename"
platform="$(extract images.0.platform 2>/dev/null)" \
  || fail "the first AppIcon image has no platform"
size="$(extract images.0.size 2>/dev/null)" \
  || fail "the first AppIcon image has no size"

[[ "$platform" == "watchos" ]] \
  || fail "AppIcon image platform is '$platform', expected 'watchos'"
[[ "$size" == "1024x1024" ]] \
  || fail "AppIcon image size is '$size', expected '1024x1024'"

[[ "$filename" != /* && "$filename" != *".."* ]] \
  || fail "AppIcon filename is not a safe asset-relative path: $filename"
image="$ICON_DIR/$filename"
[[ -f "$image" ]] || fail "AppIcon references missing file: $filename"

format="$(sips -g format "$image" 2>/dev/null | awk '/format:/ {print $2}')"
width="$(sips -g pixelWidth "$image" 2>/dev/null | awk '/pixelWidth:/ {print $2}')"
height="$(sips -g pixelHeight "$image" 2>/dev/null | awk '/pixelHeight:/ {print $2}')"
alpha="$(sips -g hasAlpha "$image" 2>/dev/null | awk '/hasAlpha:/ {print $2}')"

[[ "$format" == "png" ]] || fail "AppIcon is not a PNG (format: ${format:-unknown})"
[[ "$width" == "1024" && "$height" == "1024" ]] \
  || fail "AppIcon dimensions are ${width:-unknown}x${height:-unknown}, expected 1024x1024"
[[ "$alpha" == "no" ]] || fail "AppIcon must not have an alpha channel"

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

echo "watch-appicon: valid watchOS AppIcon ($filename, ${width}x${height}, alpha=${alpha})"
