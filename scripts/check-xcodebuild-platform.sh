#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# A global SDK override is unsafe for this project because the Cadence scheme
# embeds the Watch target. Keep destination-based builds as the only repository
# documented/automated path so actool selects the platform for each target.
if rg -n --hidden \
  --glob '!.git/**' \
  --glob '!scripts/check-xcodebuild-platform.sh' \
  --glob '!current_status.md' \
  -- '-sdk[=[:space:]]+(iphoneos|iphonesimulator|watchos|watchsimulator)|SDKROOT[[:space:]]*=[[:space:]]*(iphoneos|iphonesimulator|watchos|watchsimulator)' \
  "$ROOT/Makefile" "$ROOT/README.md" "$ROOT/CLAUDE.md" \
  "$ROOT/docs/TESTING.md" "$ROOT/.github/workflows" "$ROOT/scripts"; then
  echo "xcodebuild-platform: found a global SDK override in repository build instructions" >&2
  echo "xcodebuild-platform: use a destination, e.g. -destination 'generic/platform=iOS'" >&2
  exit 1
fi

echo "xcodebuild-platform: destination-based build contract OK"
