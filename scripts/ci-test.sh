#!/usr/bin/env bash
# One host suite, including ProductionFlowHarnessTests. Serial XCTest avoids
# per-case parallel scheduling/setup overhead; Swift Testing keeps its own runner.
# Set CADENCE_TEST_MODE=parallel and CADENCE_TEST_WORKERS=N to benchmark workers.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
case "${CADENCE_TEST_MODE:-serial}" in
  serial) runner=(--no-parallel) ;;
  parallel)
    workers="${CADENCE_TEST_WORKERS:-3}"
    if [[ ! "$workers" =~ ^[1-9][0-9]*$ ]]; then
      echo 'CADENCE_TEST_WORKERS must be a positive integer' >&2; exit 2
    fi
    runner=(--parallel --num-workers "$workers")
    ;;
  *) echo 'CADENCE_TEST_MODE must be serial or parallel' >&2; exit 2 ;;
esac
exec swift test --package-path CadenceCore "${runner[@]}" "$@"
