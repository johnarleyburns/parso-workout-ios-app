# Handoff prompt — launch-blocker fixes

Paste the following to the implementing agent (one phase per session recommended):

---

Implement the launch-blocker plan at `plans/launch-blockers/2026-07-18/00-plan.md` (decisions in `decisions.md` are settled — do not re-litigate). Read `CLAUDE.md` first and follow its dev methodology and post-task checklist exactly.

Work **one phase at a time**, in order: Phase 1 (lifecycle) → 2 (SessionView perf) → 3 (swap fix) → 4 (per-rep autofill) on stacked branches; Phase 5 (Home today-list) is independent off `main` and may be done any time.

Hard requirements, all phases:
- A workout must NEVER be ended by the system — only explicit user taps end it. Auto-pause is the only permitted automatic action (idle watchdog, crash recovery). The `IdleWatchdog` type must make auto-end unrepresentable (no end case in `TickResult`), proven by tests.
- Crash/upgrade mid-workout → relaunch shows the "Resume Workout" card (adopted paused, dead gap excluded from the clock); never auto-present, never discard.
- All logic in CadenceCore/CadenceFeatures (Foundation/SwiftData/Observation only — no SwiftUI imports), covered by the test lists in the plan via headless `swift test`. The perf phase must include the recompute-count proof tests (`equalSignatureNeverRebuilds`, `loggingASetRebuildsExactlyOnce`).
- XCUITest smoke suite: edit existing steps only (Phase 1's push→fullScreenCover change); never add tests; preserve accessibility identifiers (`home.resume`, `session.*`).
- Zero schema changes. LOC ratchets in `scripts/check-test-pyramid.sh` must be lowered as SessionView shrinks; new files <400 LOC.
- Phase 4 must render the e1RM suggestion with a tappable `CitationLink` using the existing `oneRMEstimation` id and update its `docs/CITATIONS.md` entry.

Per phase: verify with `swift test` + `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build`, update `current_state.md`, commit with a conventional message referencing spec IDs (FR-1, field-testing §02/§04) and the Co-Authored-By trailer, merge to `main`, push, and report the SHA + CI status. The plan's final "Verification" section lists the on-device field script for the owner.

---
