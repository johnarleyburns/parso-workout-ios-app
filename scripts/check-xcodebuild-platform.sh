#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# A global SDK override is unsafe for this project because the Cadence scheme
# embeds the Watch target. Keep destination-based builds as the only repository
# documented/automated path so actool selects the platform for each target.
PATTERN='-sdk[=[:space:]]+(iphoneos|iphonesimulator|watchos|watchsimulator)|SDKROOT[[:space:]]*=[[:space:]]*(iphoneos|iphonesimulator|watchos|watchsimulator)'
TARGETS=("$ROOT/Makefile" "$ROOT/README.md" "$ROOT/CLAUDE.md" \
  "$ROOT/docs/TESTING.md" "$ROOT/.github/workflows" "$ROOT/scripts")

# ripgrep is not guaranteed on CI runners; fall back to POSIX grep.
search() {
  if command -v rg >/dev/null 2>&1; then
    rg -n --hidden \
      --glob '!.git/**' \
      --glob '!scripts/check-xcodebuild-platform.sh' \
      --glob '!**/scripts/tests/test-xcodebuild-safe.sh' \
      --glob '!current_status.md' \
      -- "$PATTERN" "${TARGETS[@]}"
  else
    local existing=() t
    for t in "${TARGETS[@]}"; do [ -e "$t" ] && existing+=("$t"); done
    grep -rnE \
      --exclude='check-xcodebuild-platform.sh' \
      --exclude='test-xcodebuild-safe.sh' \
      --exclude='current_status.md' \
      --exclude-dir=.git \
      -- "$PATTERN" "${existing[@]}"
  fi
}

if search; then
  echo "xcodebuild-platform: found a global SDK override in repository build instructions" >&2
  echo "xcodebuild-platform: use a destination, e.g. -destination 'generic/platform=iOS'" >&2
  exit 1
fi

echo "xcodebuild-platform: destination-based build contract OK"
