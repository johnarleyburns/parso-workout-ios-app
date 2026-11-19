#!/usr/bin/env bash
# One host suite, including ProductionFlowHarnessTests. All tests are Swift
# Testing, which schedules itself concurrently regardless of SwiftPM's
# --parallel/--no-parallel (that flag only shards separate XCTest worker
# processes, and there is no XCTest content left to shard).
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
exec swift test --package-path CadenceCore "$@"
