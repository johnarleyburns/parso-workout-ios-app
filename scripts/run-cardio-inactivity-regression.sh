#!/usr/bin/env bash
# Cardio/interval inactivity regression suite (issue #488). Headless: manual clocks and fake
# transports only; no simulator, HealthKit, Watch or real waiting. Runs three times to prove
# determinism. Failure names are per-platform (phone/watch/interval/guard).
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
for i in 1 2 3; do
  echo "=== cardio inactivity regression run $i ==="
  swift test --package-path CadenceCore --filter 'CardioInactivityRegressionSuite|CardioTerminalOwnershipGuardTests|PhoneCardioInactivityCoordinatorTests|WatchCardioInactivityTests|IntervalInactivityEvidenceAdapterTests|CardioInactivityPolicyTests'
done
