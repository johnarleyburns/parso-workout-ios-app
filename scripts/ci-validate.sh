#!/usr/bin/env bash
# Single source of truth for PR validation. Used by the PR Swift Validation
# workflow, the issue agent and the repair agent so the three cannot drift.
# Runs everything headless: no simulator is booted.
# Usage: scripts/ci-validate.sh [--fast]   (--fast = static checks only)
set -euo pipefail
cd "${CI_VALIDATE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

step() { echo "::group::$*"; echo "=== $* ==="; }
endstep() { echo "::endgroup::"; }

step "Shell syntax"
while IFS= read -r f; do
  bash -n "$f" || { echo "Shell syntax error: $f" >&2; exit 1; }
done < <(git ls-files '*.sh')
endstep

step "Workflow YAML"
while IFS= read -r f; do
  ruby -ryaml -e 'YAML.safe_load(File.read(ARGV[0]), aliases: true)' "$f" \
    || { echo "Invalid workflow YAML: $f" >&2; exit 1; }
done < <(git ls-files '.github/workflows/*.yml')
endstep

step "Automation regression tests"
bash scripts/tests/test-issue-pr-policy.sh
bash scripts/tests/test-testflight-delivery-body.sh
if [[ -f scripts/tests/test-xcodebuild-safe.sh ]]; then
  /bin/bash scripts/tests/test-xcodebuild-safe.sh
fi
if [[ -f scripts/tests/test-pr-maintenance.sh && -f .github/scripts/pr-maintenance.sh ]]; then
  bash scripts/tests/test-pr-maintenance.sh
fi
endstep

[[ "${1:-}" == "--fast" ]] && exit 0

step "Swift package tests"
swift test --package-path CadenceCore --parallel
endstep

step "iPhone + embedded Watch build"
# Release configuration, same as the release archive, so deprecation warnings
# the archive gate would reject surface here before merge.
build_log="$(mktemp -t ci-validate-build.XXXXXX)"
bash scripts/xcodebuild-safe.sh -project Cadence/Cadence.xcodeproj -scheme Cadence \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$build_log"
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
