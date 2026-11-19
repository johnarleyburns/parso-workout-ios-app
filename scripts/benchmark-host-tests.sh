#!/usr/bin/env bash
# Compile once, then time the full suite (twice, for run-to-run variance) on one
# Mac runner. Swift Testing schedules itself concurrently regardless of how it's
# invoked, so there is no serial/parallel mode left to compare.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
output="${RUNNER_TEMP:-/tmp}/cadence-test-benchmark"
mkdir -p "$output"
: > "$output/timing-seconds.csv"
swift build --package-path CadenceCore --build-tests 2>&1 | tee "$output/build.log"
for run in run-1 run-2; do
  start=$SECONDS
  bash scripts/ci-test.sh --skip-build 2>&1 | tee "$output/$run.log"
  echo "$run,$((SECONDS - start))" | tee -a "$output/timing-seconds.csv"
done
# Keep the expensive repeated search benchmark in this dedicated lane.
CADENCE_FULL_BENCHMARKS=1 bash scripts/ci-test.sh --skip-build \
  --filter ExerciseSearchIndexTests/reusingIndexBeatsRebuildingPerKeystroke \
  2>&1 | tee "$output/search-benchmark.log"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo '### Host test benchmark (same SHA, one compilation)'
    echo 'Run, elapsed seconds:'
    cat "$output/timing-seconds.csv"
  } >> "$GITHUB_STEP_SUMMARY"
fi
