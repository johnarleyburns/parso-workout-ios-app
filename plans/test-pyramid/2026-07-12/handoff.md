# Handoff prompt (paste-ready)

Copy the block below into a fresh Claude Code session in this repo. Run one phase per session —
Phase 3 especially should get its own session with a clean context.

---

```
Read plans/test-pyramid/2026-07-12/00-overview.md end to end before doing anything.

Context: our 148 XCUITests are unusable — they time out and saturate the machine, and CI
doesn't even run them. The root cause is that ~15k LOC of app logic lives inside SwiftUI
View structs (SessionView.swift is 1,778 LOC, HomeView.swift is 1,135 LOC), so XCUITest is
the only thing that can reach it. The plan moves that logic into a new `CadenceFeatures`
SwiftPM target that `swift test` can exercise headlessly, then culls the UI suite to ~10
smoke tests.

Implement **Phase <N>** only. Do not start the next phase.

Rules:
- `CadenceFeatures` imports Foundation + SwiftData + Observation ONLY. No SwiftUI, no
  HealthKit, no StoreKit, no UIKit. If an extraction wants a Color or a View, return a
  semantic enum instead and let the view map it.
- Extractions are MOVES, not rewrites. Preserve behavior exactly. Any behavior change is a
  bug, not an improvement.
- Keep `@Query` in the view. Pass its results into a pure function that returns a state
  struct; the view renders the struct.
- Inject `Clock` instead of calling `Date()`. Follow the existing pattern — CadenceCore's
  `WorkoutClock` / `PhaseCountdownClock` already take an injected `now:`.
- Every extracted function gets unit tests in `CadenceFeaturesTests`. XCTest, to match the
  791 existing tests in `CadenceCoreTests`.
- Do NOT delete any XCUITest until its replacement unit test has landed and is green. In
  phases 1-4, the old UI test must still pass against the refactored app — that's the proof
  the move didn't change behavior.
- Small, focused commits. One function group at a time, especially in Phase 3.

Verify with `cd CadenceCore && swift test` before committing, and report the actual test
count and result. Then follow the post-task checklist in CLAUDE.md.
```

---

## Phase order and what each session should produce

| Phase | Branch | Deliverable | Gate |
|---|---|---|---|
| 0 | `test-pyramid-0-scaffold` | `CadenceFeatures` + `CadenceFixtures` targets, `Clock`, fixtures lifted from `UITestSeed.swift`, Makefile `test`/`smoke`/`ci`, CI picks up the new test target | `swift test` green, app still builds |
| 1 | `test-pyramid-1-presenters` | `Format`, `AssessmentDisplay`, `HistoryPresenter`, `YourWeekPresenter`, `ProgressPresenter`, `ExportPresenter` + tests | `swift test` green; UI suite still passes |
| 2 | `test-pyramid-2-models` | `ActiveWorkoutModel`, `IntervalRunner`, `RestTimerModel`, `CardioRecorder`, `IntervalCueScheduler`, `SettingsStore`, `EntitlementResolver` + tests | `swift test` green; the 23 app-hosted tests in `CadenceTests` move to `swift test` |
| 3 | `test-pyramid-3-viewmodels` | `SessionViewModel`, `HomeCoachModel` (incl. **`CoachSignature` tests** — highest value in the whole plan), `EditablePlan` | `swift test` green; `SessionView` and `HomeView` both under 400 LOC |
| 4 | `test-pyramid-4-routing` | `CoachRouter`, `OnboardingModel` + tests | `swift test` green |
| 5 | `test-pyramid-5-smoke` | 10 smoke tests; delete 37 UI test files; rewrite `Cadence.xctestplan` (no retries); `waitTap` 25s→5s; `UIView.setAnimationsEnabled(false)` under `-uiTest` | `make smoke` under 5 min, serial, zero retries |
| 6 | `test-pyramid-6-guardrails` | `scripts/check-test-pyramid.sh` in CI; `CLAUDE.md` convention | CI red if a View exceeds 400 LOC or the UI suite exceeds 12 tests |

Phase 3 depends on 1 and 2 — **stack its branch on them** rather than branching off `main`
(per the CLAUDE.md methodology).

## Definition of done

- `swift test`: **791 → ~1,050–1,100** tests, still runs in seconds, still no simulator.
- XCUITest: **148 → 10**, `make smoke` under 5 minutes serially with zero retries.
- `make test` — the everyday gate — needs **no simulator at all**.
- CI runs the unit suite on every push and the smoke suite on the GitHub macOS runner, so the
  laptop never has to.
