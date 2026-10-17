#!/usr/bin/env bash
# Static companion to xcodebuild-safe.sh: reject a CI command that could boot
# an iOS/watchOS simulator before a runner ever executes it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if rg -n -i \
  --glob '!check-ci-no-simulators.sh' \
  --glob '!xcodebuild-safe.sh' \
  --glob '!test-xcodebuild-safe.sh' \
  '(simctl[[:space:]]+(boot|bootstatus)|xcodebuild[^\n]*(test-without-building|[[:space:]]test([[:space:]]|$))|destination[^\n]*(ios|watchos)[^\n]*simulator|platform=(ios|watchos)[[:space:]]+simulator)' \
  "$ROOT/.github/workflows" "$ROOT/.github/scripts" "$ROOT/scripts"; then
  echo "ci-no-simulators: CI commands may not boot or test against an iOS/watchOS simulator" >&2
  exit 1
fi

echo "ci-no-simulators: CI command contract OK"
