#!/usr/bin/env bash
# Test the real guard against both a negative-test fixture and an unsafe build.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/scripts/tests" "$fixture/docs" "$fixture/.github/workflows"
cp "$root/scripts/check-xcodebuild-platform.sh" "$fixture/scripts/"
cp "$root/scripts/tests/test-xcodebuild-safe.sh" "$fixture/scripts/tests/"
touch "$fixture/Makefile" "$fixture/README.md" "$fixture/CLAUDE.md" "$fixture/docs/TESTING.md"
bash "$fixture/scripts/check-xcodebuild-platform.sh" >/dev/null
sdkflag=-sdk
printf '%s %s %s\n' xcodebuild "$sdkflag" iphoneos > "$fixture/scripts/unsafe-build.sh"
if bash "$fixture/scripts/check-xcodebuild-platform.sh" >/dev/null 2>&1; then
  echo 'SDK guard accepted an unsafe production build command' >&2
  exit 1
fi
echo 'SDK guard: negative fixture allowed, unsafe build rejected'
