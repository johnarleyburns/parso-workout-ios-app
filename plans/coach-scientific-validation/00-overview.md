# Coach Scientific Validation Test Suite

## Purpose

A clean-room, black-box validation of the Cadence coach. Each test feeds curated
workout history to the coach, predicts what SHOULD happen based on published
exercise science (cited from the existing `CitationRegistry`), asserts the
actual output, and reports the result in a table.

## Design Rules

1. **Clean-room / black-box**: Tests only use the public API
   (`CoachSnapshotBuilder.build()`, `CoachDecisionEngine.run()`,
   `CoachFacts.make()`). No reading of scoring internals, eligibility policies,
   or optimizer algorithms.

2. **Every test cites science**: Each assertion carries one or more citation IDs
   from `CitationRegistry.all` that justify the expected behavior.

3. **Deminimus methodology**: Start with a baseline scenario where the coach
   gives a known-good recommendation. Make ONE small change (add a workout,
   toggle a preference, change a setting). Predict the delta. Verify.

4. **Table output**: A shell script runs the tests and produces a markdown
   results table showing predicate, actual, pass/fail, and citations.

## Test Architecture

Single file: `CadenceCore/Tests/CadenceCoreTests/CoachScientificValidationTests.swift`

Runner: `scripts/run-coach-validation.sh`
Parser: `scripts/parse-coach-results.py`

## Test Categories

### Domain A: Recovery & Safety Gates (4 tests)

| # | Test | Citation | Deminimus From |
|---|------|----------|----------------|
| A1 | Pain concern blocks hard training → rest primary | `meeusenOvertraining2013` | Cold start |
| A2 | 48h same-lift recovery gate — squat <48h ago → squat not in primary | `parejaBlancoRecovery2020` | A1 (no pain, add squat) |
| A3 | 6+ consecutive hard days → overtraining warning | `meeusenOvertraining2013`, `drewFinchInjury2016` | A2 (add 5+ hard days) |
| A4 | >20 sets for one body part in a week → excessive volume warning | `pellandDoseResponse2026` | A2 (add 21+ chest sets) |

### Domain B: Balance & Priority (5 tests)

| # | Test | Citation | Deminimus From |
|---|------|----------|----------------|
| B1 | Aerobic deficit → primary is aerobic | `ekelundActivityMortality2016` | Cold start (add 2 strength) |
| B2 | Strength deficit → primary is strength | `schoenfeld2021` | B1 (swap strength/cardio) |
| B3 | Both floors met → VO2/anaerobic become candidates | `crowleyVO2Intensity2022`, `poonHIIT2024` | B1 (meet both) |
| B4 | 3x/week target → weekly plan spreads 2 remaining across different days | `frequencyMeta` | B1 (set 3 strength/wk) |
| B5 | Two-a-day completion → planAdherence = .planComplete | `schumannConcurrent2022` | B4 (enable two-a-days) |

### Domain C: Preference Learning (3 tests)

| # | Test | Citation | Deminimus From |
|---|------|----------|----------------|
| C1 | Cycle preference → coach picks cycle for aerobic | User preference learning | B1 (add cycle pref) |
| C2 | HighImpact avoidance → run not primary when low-impact available | User preference learning | C1 (add avoidance) |
| C3 | Strength exercise preference → coach uses most-trained lifts | Exercise preference | Cold start (log specific lifts) |

### Domain D: Assessment & Baseline (3 tests)

| # | Test | Citation | Deminimus From |
|---|------|----------|----------------|
| D1 | No baseline for trained system → assessment prompt | `oneRMEstimation` | Cold start (add 3 strength) |
| D2 | Aerobic base established → threshold tempo appears | `kaufmannThreshold2023` | D1 (swap for cardio) |
| D3 | Fresh assessment → no "add baseline" nudge | `fieldFitnessReliability2022` | D1 (add assessment) |

### Domain E: Deminimus Edge Cases (5 tests)

| # | Test | Citation | Deminimus From |
|---|------|----------|----------------|
| E1 | Soft-deleted sessions ignored | N/A (data integrity) | B1 (delete a session) |
| E2 | Future-dated events excluded from balance | N/A (data integrity) | B1 (add future event) |
| E3 | Beginner <5 sessions → Full-body A/B candidates | `schoenfeld2021` | Cold start (beginner) |
| E4 | Consecutive hard days <3 → recovery NOT primary | `meeusenOvertraining2013` | A3 (only 2 hard days) |
| E5 | Deterministic: identical inputs → identical outputs | N/A (system integrity) | Any test (call twice) |

## Expected Output

```
| #  | Test                                | Expected                       | Actual                         | Result | Citations                          |
|----|-------------------------------------|--------------------------------|--------------------------------|--------|------------------------------------|
| A1 | Pain blocks hard training           | primary = rest                 | rest                           | PASS   | meeusenOvertraining2013            |
| A2 | 48h same-lift recovery gate         | squat deferred/not primary     | no squat in primary            | PASS   | parejaBlancoRecovery2020           |
| ...| ...                                 | ...                            | ...                            | ...    | ...                                |
```

Summary:
```
PASS: X/20 | FAIL: Y/20 | PARTIAL: Z/20
```

## Scientific Justifications

See `CadenceCore/Sources/CadenceCore/Citation.swift` for full citation details.
Each test references citation IDs from `CitationRegistry.all`.
