#!/usr/bin/env bash
# Hermetic production-flow harness (issue #306). Headless: no simulator, network,
# signing secrets, HealthKit hardware or real sleeps. Used by the issue worker
# and by scripts/ci-validate.sh (so PR validation runs it).
# Usage: scripts/run-verification-harness.sh [--self-test]
#   --self-test  also proves the harness FAILS when a production binding is
#                removed (mutation applied to a throwaway copy of the package).
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
export HARNESS_ARTIFACT_DIR="${HARNESS_ARTIFACT_DIR:-$PWD/.harness-artifacts}"
mkdir -p "$HARNESS_ARTIFACT_DIR"
FILTER='ProductionFlowHarnessTests'

run() { swift test --package-path "$1" --filter "$FILTER"; }

echo "=== harness run 1 ==="
run CadenceCore
echo "=== harness run 2 (determinism) ==="
run CadenceCore

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/cladiron-harness-mutation.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  rsync -a --exclude .build CadenceCore/ "$tmp/CadenceCore/"
  target="$tmp/CadenceCore/Sources/CadenceFeatures/WatchHeartRateReceiver.swift"
  sed -i.bak 's/guard let request = expectedRequestID(message.phoneWorkoutSessionID) else { return reject(.sessionMismatch) }/let request = expectedRequestID(message.phoneWorkoutSessionID) ?? message.watchRequestID/' "$target"
  if cmp -s "$target" "$target.bak"; then echo "self-test: mutation did not apply" >&2; exit 2; fi
  if run "$tmp/CadenceCore" >/dev/null 2>&1; then
    echo "self-test FAILED: harness did not detect the removed production binding" >&2
    exit 1
  fi
  echo "self-test ok: removed binding was detected"
fi
echo "harness ok (artifacts: $HARNESS_ARTIFACT_DIR)"
