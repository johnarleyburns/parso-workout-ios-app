#!/bin/bash
# run-coach-validation.sh
# Runs the CoachScientificValidationTests suite and produces a results table.
# Usage: ./scripts/run-coach-validation.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Coach Scientific Validation Suite ==="
echo "Running tests..."
echo ""

# Run tests with verbose output, capture to log
TEST_LOG="/tmp/coach-validation-$(date +%s).log"
cd "$PROJECT_DIR"
swift test --package-path CadenceCore --filter "CoachScientificValidationTests" 2>&1 | tee "$TEST_LOG"

# Parse results
echo ""
echo "=== Results ==="
echo ""

# Count passes and failures
PASSED=$(grep -c "passed (" "$TEST_LOG" || true)
FAILED=$(grep -c "failed (" "$TEST_LOG" || true)
TOTAL=$((PASSED + FAILED))

echo "Total: $TOTAL | Passed: $PASSED | Failed: $FAILED"

# Extract individual test results
echo ""
echo "---"
echo ""

# Generate a markdown table from the test log
python3 "$SCRIPT_DIR/parse-coach-results.py" "$TEST_LOG"

echo ""
echo "Full log: $TEST_LOG"
