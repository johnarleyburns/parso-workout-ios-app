#!/usr/bin/env bash
# Execute the wrapper through /bin/bash (the system shell on hosted macOS) with
# a stand-in xcodebuild.  This proves prohibited arguments fail before Xcode
# could launch and permitted generic-device builds retain their arguments.
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/xcodebuild-safe.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${XCODEBUILD_SAFE_CAPTURE:?}"
EOF
chmod +x "$tmp/bin/xcodebuild"

expect_rejected() {
  : > "$tmp/capture"
  if PATH="$tmp/bin:$PATH" XCODEBUILD_SAFE_CAPTURE="$tmp/capture" GITHUB_ACTIONS=true \
      /bin/bash "$root/scripts/xcodebuild-safe.sh" "$@" >/dev/null 2>&1; then
    echo "expected rejection: $*" >&2; exit 1
  fi
  test ! -s "$tmp/capture" || { echo "xcodebuild was launched for: $*" >&2; exit 1; }
}

expect_rejected -destination 'platform=iOS Simulator,name=iPhone' build
expect_rejected test -project Cadence/Cadence.xcodeproj
expect_rejected -sdk iphoneos build

: > "$tmp/capture"
PATH="$tmp/bin:$PATH" XCODEBUILD_SAFE_CAPTURE="$tmp/capture" GITHUB_ACTIONS=true \
  /bin/bash "$root/scripts/xcodebuild-safe.sh" -destination 'generic/platform=iOS' build
grep -qx -- '-destination' "$tmp/capture"
grep -qx -- 'generic/platform=iOS' "$tmp/capture"
grep -qx -- 'build' "$tmp/capture"

echo "xcodebuild-safe Bash compatibility regression tests passed (Bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]})"
