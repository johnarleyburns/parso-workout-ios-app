#!/usr/bin/env bash
# Compile once, then compare the exact same full suite/commit on one Mac runner.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
output="${RUNNER_TEMP:-/tmp}/cadence-test-benchmark"
mkdir -p "$output"
: > "$output/timing-seconds.csv"
swift build --package-path CadenceCore --build-tests 2>&1 | tee "$output/build.log"
for run in serial parallel-2 parallel-3 serial-repeat; do
  mode=serial
  workers=3
  case "$run" in parallel-*) mode=parallel; workers="${run#parallel-}" ;; esac
  start=$SECONDS
  CADENCE_TEST_MODE="$mode" CADENCE_TEST_WORKERS="$workers" \
    bash scripts/ci-test.sh --skip-build 2>&1 | tee "$output/$run.log"
  echo "$run,$((SECONDS - start))" | tee -a "$output/timing-seconds.csv"
done
# Keep the expensive repeated search benchmark in this dedicated lane.
CADENCE_FULL_BENCHMARKS=1 bash scripts/ci-test.sh --skip-build \
  --filter ExerciseSearchIndexTests/testReusingIndexBeatsRebuildingPerKeystroke \
  2>&1 | tee "$output/search-benchmark.log"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo '### Host test benchmark (same SHA, one compilation)'
    echo 'Mode, elapsed seconds:'
    cat "$output/timing-seconds.csv"
  } >> "$GITHUB_STEP_SUMMARY"
fi
