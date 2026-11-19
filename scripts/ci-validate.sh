#!/usr/bin/env bash
# Single source of truth for PR validation. Used by the PR Swift Validation
# workflow, the issue agent and the repair agent so the three cannot drift.
# Runs everything headless: no simulator is booted.
# Usage: scripts/ci-validate.sh [--fast|--tests|--build]
# Default: all stages sequentially for issue/repair callers. CI splits runners.
set -euo pipefail
cd "${CI_VALIDATE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

step() { echo "::group::$*"; echo "=== $* ==="; }
endstep() { echo "::endgroup::"; }

mode="${1:---all}"
case "$mode" in --all|--fast|--tests|--build) ;; *) echo "Unknown validation mode: $mode" >&2; exit 2 ;; esac
if [[ "$mode" == --all || "$mode" == --fast ]]; then
  step "Shell syntax"
  while IFS= read -r f; do
    bash -n "$f" || { echo "Shell syntax error: $f" >&2; exit 1; }
  done < <(git ls-files '*.sh')
  endstep

  step "Workflow YAML"
  while IFS= read -r f; do
    ruby -ryaml -e 'YAML.safe_load(File.read(ARGV[0]), aliases: true)' "$f" \
      || { echo "Invalid workflow YAML: $f" >&2; exit 1; }
  done < <(git ls-files '.github/workflows/*.yml' '.github/actions/*/action.yml')
  endstep

  step "TestFlight crash collector"
  ruby -c .github/scripts/testflight-crash-intake.rb
  ruby scripts/tests/test-testflight-crash-intake.rb
  endstep

  step "Automation regression tests"
  python3 scripts/tests/test_ci_throughput.py
  python3 scripts/tests/test_module_boundaries.py
  bash scripts/tests/test-xcodebuild-platform.sh
  bash scripts/tests/test-issue-pr-policy.sh
  bash scripts/tests/test-agent-invocation.sh
  bash scripts/tests/test-issue-pr-introspection.sh
  bash scripts/tests/test-issue-backlog-order.sh
  bash scripts/tests/test-release-repair-policy.sh
  bash scripts/tests/test-testflight-delivery-body.sh
  bash scripts/tests/test-testflight-reconciler-discovery.sh
  if [[ -f scripts/tests/test-xcodebuild-safe.sh ]]; then
    /bin/bash scripts/tests/test-xcodebuild-safe.sh
  fi
  if [[ -f scripts/tests/test-pr-maintenance.sh && -f .github/scripts/pr-maintenance.sh ]]; then
    bash scripts/tests/test-pr-maintenance.sh
  fi
  endstep

fi
[[ "$mode" == --fast ]] && exit 0

if [[ "$mode" == --all || "$mode" == --tests ]]; then
step "Swift package tests (includes production-flow harness once)"
test_log="${RUNNER_TEMP:-/tmp}/ci-swift-test.log"
bash scripts/ci-test.sh 2>&1 | tee "$test_log"
bash scripts/check-owned-warnings.sh "$test_log"
bash scripts/test-check-owned-warnings.sh
endstep
fi
[[ "$mode" == --tests ]] && exit 0

step "iPhone + embedded Watch build"
# Release configuration, same as the release archive, so deprecation warnings
# the archive gate would reject surface here before merge.
# Keep a stable path so the workflow can upload the complete transcript even
# when xcodebuild or the warning gate fails. GitHub's rendered step log is
# size-limited, while this file remains inspectable as an artifact.
build_log="${RUNNER_TEMP:-/tmp}/ci-validate-build.log"
rm -f "$build_log"
bash scripts/xcodebuild-safe.sh -project Cadence/Cadence.xcodeproj -scheme Cadence \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "${CADENCE_DERIVED_DATA:-$PWD/.build/ci-derived-device}" \
  -clonedSourcePackagesDirPath "${CADENCE_SOURCE_PACKAGES:-$PWD/.build/ci-source-packages}" \
  -showBuildTimingSummary CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$build_log"
endstep

step "Owned warning gate (app build)"
bash scripts/check-owned-warnings.sh "$build_log"
bash scripts/test-check-owned-warnings.sh
endstep

step "Guardrails"
for g in check-test-pyramid check-no-network check-history-safety check-watch-appicon \
         check-watch-background-modes check-xcodebuild-platform check-ci-no-simulators check-release-safety; do
  bash "scripts/$g.sh"
done
endstep
