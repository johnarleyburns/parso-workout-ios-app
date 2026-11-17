#!/usr/bin/env bash
# Cold + incremental xcodebuild timing, baseline ref vs HEAD, for the
# shared-light-modules extraction (docs/architecture/shared-light-modules.md).
# "No advertised speedup until measured" — this script produces the
# before/after compiler-task-summary evidence that doc's phased-delivery
# acceptance criteria require. It is a manual, one-off comparison, not a CI
# gate, and it needs a real Xcode/macOS toolchain: it refuses to run anywhere
# xcodebuild is unavailable (this repo's Linux CI/dev host included).
#
# Usage: scripts/benchmark-module-extraction.sh --baseline <git-ref> [--scheme <name>]...
#   Default schemes: "Cadence" "Cadence Watch App"  (each embeds its widget
#   extension, so building the app scheme already times the widget build.)
#
# Builds run sequentially — never two Xcode jobs overlapping, per this repo's
# "Local iPhone and Watch builds must run sequentially" rule — and each
# (ref, scheme) pair gets its own throwaway derived-data dir and git worktree,
# so this never touches the caller's working tree or shared DerivedData.
set -euo pipefail

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "benchmark-module-extraction: xcodebuild not found — this benchmark requires macOS/Xcode." >&2
  echo "benchmark-module-extraction: run it on a Mac; it cannot run on this host." >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

baseline=""
schemes=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline) baseline="$2"; shift 2 ;;
    --scheme) schemes+=("$2"); shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$baseline" ]]; then
  echo "usage: $0 --baseline <git-ref> [--scheme <name>]..." >&2
  exit 2
fi
if [[ ${#schemes[@]} -eq 0 ]]; then
  schemes=("Cadence" "Cadence Watch App")
fi

out="${CADENCE_BENCHMARK_OUT:-/tmp/cadence-module-benchmark-$(date +%s)}"
mkdir -p "$out"
summary="$out/summary.md"
echo "# Module extraction build-timing benchmark" > "$summary"
echo "" >> "$summary"
echo "Baseline: \`$baseline\`  HEAD: \`$(git rev-parse --short HEAD)\`" >> "$summary"
echo "" >> "$summary"

worktrees=()
cleanup() {
  for wt in "${worktrees[@]}"; do
    git worktree remove --force "$wt" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

checkout_ref() {
  # Sets the global `wt` variable rather than echoing a return value: this
  # must run in the main shell, not a $(...) subshell, or the `worktrees`
  # array it appends to never reaches the cleanup trap.
  local ref="$1" label="$2"
  wt="$out/worktree-$label"
  git worktree add --detach "$wt" "$ref" >/dev/null
  worktrees+=("$wt")
}

destination_for() {
  case "$1" in
    *Watch*) echo "generic/platform=watchOS" ;;
    *) echo "generic/platform=iOS" ;;
  esac
}

# A trivial, behavior-preserving touch to force a real (small) recompile for
# the incremental-build measurement. Deliberately a root app-entry file that
# predates this whole extraction (not a file this refactor moves/creates),
# so it exists unchanged at both the pre-extraction baseline ref and HEAD.
touch_target_for() {
  local wt="$1" scheme="$2"
  local file
  case "$scheme" in
    *Watch*) file="$wt/Cadence/Cadence Watch App Watch App/Cadence_Watch_AppApp.swift" ;;
    *) file="$wt/Cadence/Cadence/CadenceApp.swift" ;;
  esac
  echo "// benchmark touch $(date +%s)" >> "$file"
}

build_one() {
  local wt="$1" scheme="$2" dd="$3" log="$4"
  bash "$wt/scripts/xcodebuild-safe.sh" \
    -project "$wt/Cadence/Cadence.xcodeproj" -scheme "$scheme" \
    -destination "$(destination_for "$scheme")" \
    -derivedDataPath "$dd" CODE_SIGNING_ALLOWED=NO \
    -showBuildTimingSummary build > "$log" 2>&1
}

for label in baseline head; do
  if [[ "$label" == "baseline" ]]; then ref="$baseline"; else ref="HEAD"; fi
  checkout_ref "$ref" "$label"
  for scheme in "${schemes[@]}"; do
    slug=$(echo "$scheme" | tr -c 'A-Za-z0-9' '_')
    dd="$out/dd-$label-$slug"
    cold_log="$out/$label-$slug-cold.log"
    incr_log="$out/$label-$slug-incremental.log"

    echo "== $label / $scheme : cold build ==" | tee -a "$summary"
    cold_start=$SECONDS
    build_one "$wt" "$scheme" "$dd" "$cold_log"
    cold_elapsed=$((SECONDS - cold_start))

    touch_target_for "$wt" "$scheme"

    echo "== $label / $scheme : incremental build ==" | tee -a "$summary"
    incr_start=$SECONDS
    build_one "$wt" "$scheme" "$dd" "$incr_log"
    incr_elapsed=$((SECONDS - incr_start))

    {
      echo ""
      echo "## $label / $scheme"
      echo "- cold build: ${cold_elapsed}s"
      echo "- incremental build (one-file touch): ${incr_elapsed}s"
      echo ""
      echo '```'
      grep -A 30 "Build Timing Summary" "$cold_log" || echo "(no timing summary captured — check $cold_log)"
      echo '```'
    } >> "$summary"
  done
done

echo "" >> "$summary"
echo "Full logs and derived-data dirs under: $out" >> "$summary"
cat "$summary"
