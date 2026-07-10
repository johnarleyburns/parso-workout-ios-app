#!/usr/bin/env python3
"""Parse CoachScientificValidationTests output into a markdown results table."""

import re
import sys

# Test definitions with predictions and citations
TESTS = {
    "testA1_painConcernBlocksHardTraining": {
        "id": "A1",
        "name": "Pain blocks hard training",
        "expected": "Primary = rest",
        "citations": "meeusenOvertraining2013",
        "domain": "Recovery & Safety",
    },
    "testA2_48hSameLiftRecoveryBlocksSquat": {
        "id": "A2",
        "name": "48h same-lift recovery gates squat",
        "expected": "Squat deferred/blocked within 48h",
        "citations": "parejaBlancoRecovery2020",
        "domain": "Recovery & Safety",
    },
    "testA3_sixConsecutiveHardDaysTriggersWarning": {
        "id": "A3",
        "name": "6+ consecutive hard days warning",
        "expected": "Overtraining warning generated",
        "citations": "meeusenOvertraining2013, drewFinchInjury2016",
        "domain": "Recovery & Safety",
    },
    "testA4_excessiveWeeklyVolumeTriggersWarning": {
        "id": "A4",
        "name": "Excessive weekly volume warning",
        "expected": "Volume warning for >20 sets/bodypart",
        "citations": "pellandDoseResponse2026",
        "domain": "Recovery & Safety",
    },
    "testB1_aerobicDeficitRecommendsAerobic": {
        "id": "B1",
        "name": "Aerobic deficit → aerobic primary",
        "expected": "Primary = easy or moderate aerobic",
        "citations": "ekelundActivityMortality2016",
        "domain": "Balance & Priority",
    },
    "testB2_strengthDeficitRecommendsStrength": {
        "id": "B2",
        "name": "Strength deficit → strength primary",
        "expected": "Primary = strength",
        "citations": "schoenfeld2021",
        "domain": "Balance & Priority",
    },
    "testB3_bothFloorsMetSurfacesHarderOptions": {
        "id": "B3",
        "name": "Both floors met → VO2/anaerobic candidates",
        "expected": "VO2 intervals candidate present",
        "citations": "crowleyVO2Intensity2022, poonHIIT2024",
        "domain": "Balance & Priority",
    },
    "testB4_weeklyPlanDistributesStrengthAcrossDays": {
        "id": "B4",
        "name": "Weekly plan distributes strength days",
        "expected": "Future strength on distinct days",
        "citations": "frequencyMeta",
        "domain": "Balance & Priority",
    },
    "testB5_twoADayCompletionDetected": {
        "id": "B5",
        "name": "Two-a-day completion detected",
        "expected": "planAdherence = .planComplete",
        "citations": "schumannConcurrent2022",
        "domain": "Balance & Priority",
    },
    "testC1_cyclingPreferenceRememberedAndRecommended": {
        "id": "C1",
        "name": "Cycling preference → coach picks cycle",
        "expected": "Primary modality = cycle",
        "citations": "Preference learning",
        "domain": "Preference Learning",
    },
    "testC2_highImpactAvoidanceKeepsRunOut": {
        "id": "C2",
        "name": "HighImpact avoidance → run not primary",
        "expected": "Primary modality != run",
        "citations": "Preference learning",
        "domain": "Preference Learning",
    },
    "testC3_mostTrainedExercisesSurfaceInStrengthSession": {
        "id": "C3",
        "name": "Strength session includes exercises",
        "expected": "Exercises list non-empty",
        "citations": "Exercise preference",
        "domain": "Preference Learning",
    },
    "testD1_noBaselineSurfacesAssessmentPrompt": {
        "id": "D1",
        "name": "No baseline → assessment prompt",
        "expected": "Assessment candidate present",
        "citations": "oneRMEstimation",
        "domain": "Assessment & Baseline",
    },
    "testD2_aerobicBaseEnablesThresholdTempo": {
        "id": "D2",
        "name": "Aerobic base → threshold tempo surfaces",
        "expected": "Threshold tempo candidate present",
        "citations": "kaufmannThreshold2023",
        "domain": "Assessment & Baseline",
    },
    "testD3_freshAssessmentSuppressesPrompt": {
        "id": "D3",
        "name": "No events → no assessment nag",
        "expected": "No assessment candidate when untrained",
        "citations": "fieldFitnessReliability2022",
        "domain": "Assessment & Baseline",
    },
    "testE1_deletedSessionsExcluded": {
        "id": "E1",
        "name": "Soft-deleted sessions excluded",
        "expected": "Weekly chest sets = 0",
        "citations": "Data integrity",
        "domain": "Edge Cases",
    },
    "testE2_futureDatedEventsExcluded": {
        "id": "E2",
        "name": "Future events excluded from balance",
        "expected": "Last cardio = past walk",
        "citations": "Data integrity",
        "domain": "Edge Cases",
    },
    "testE3_beginnerGetsStructuredSessions": {
        "id": "E3",
        "name": "Beginner gets Full-body A/B",
        "expected": "Beginner A and B candidates present",
        "citations": "schoenfeld2021",
        "domain": "Edge Cases",
    },
    "testE4_twoConsecutiveHardDaysDoesNotForceRecovery": {
        "id": "E4",
        "name": "2 hard days → no overtraining warning",
        "expected": "No consecutive hard days warning",
        "citations": "meeusenOvertraining2013",
        "domain": "Edge Cases",
    },
    "testE5_deterministicOutput": {
        "id": "E5",
        "name": "Deterministic: same input = same output",
        "expected": "Identical primary ID both calls",
        "citations": "System integrity",
        "domain": "Edge Cases",
    },
    "test_fullSnapshotEndToEnd": {
        "id": "INT",
        "name": "Full snapshot end-to-end",
        "expected": "Non-empty decision + plan + recommendation",
        "citations": "All",
        "domain": "Integration",
    },
}


def parse_results(log_path):
    """Parse the test output log and extract pass/fail per test."""
    results = {}
    with open(log_path) as f:
        content = f.read()

    # Find all test case result lines
    # Format: "Test Case '...CoachScientificValidationTests testName]' passed (X.XX seconds)."
    test_pattern = re.compile(
        r"CoachScientificValidationTests (\S+)\]' (passed|failed)"
    )
    for match in test_pattern.finditer(content):
        test_name = match.group(1)
        status = match.group(2)
        results[test_name] = status

    # Also look for test names that started but didn't match (subtests)
    # Extract failure messages
    failure_pattern = re.compile(
        r"/([^:]+):(\d+): error:.*: (.*FAIL:.*)"
    )
    failures = {}
    for match in failure_pattern.finditer(content):
        msg = match.group(3)
        failures[len(failures)] = msg

    return results, failures


def generate_table(results, failures):
    """Generate a markdown results table grouped by domain."""
    print("## Coach Scientific Validation Results\n")

    # Header
    print("| # | Test | Expected | Result | Citations |")
    print("|---|------|----------|--------|-----------|")

    current_domain = None
    passed = 0
    failed = 0
    total = 0

    # Sort tests by ID
    sorted_tests = sorted(TESTS.items(), key=lambda x: (x[1]["domain"], x[1]["id"]))

    for test_name, info in sorted_tests:
        if info["domain"] != current_domain:
            current_domain = info["domain"]
            print(f"| | **{current_domain}** | | | |")

        status = results.get(test_name, "UNKNOWN")
        total += 1
        if status == "passed":
            passed += 1
            emoji = "PASS"
        elif status == "failed":
            failed += 1
            emoji = "FAIL"
        else:
            emoji = "???"

        print(
            f"| {info['id']} | {info['name']} | {info['expected']} | {emoji} | {info['citations']} |"
        )

    # Summary
    print(f"\n**Summary: {passed}/{total} PASS | {failed}/{total} FAIL**\n")

    if failures:
        print("### Failures\n")
        for i, msg in failures.items():
            print(f"- {msg}")
        print()

    return passed, failed, total


def main():
    if len(sys.argv) < 2:
        print("Usage: parse-coach-results.py <test-output.log>")
        sys.exit(1)

    log_path = sys.argv[1]
    results, failures = parse_results(log_path)
    passed, failed, total = generate_table(results, failures)

    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
