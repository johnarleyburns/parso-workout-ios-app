# Current Status

Updated: 2026-08-15

## Shipped and verified

- Before the current Home dashboard batch, `main` was clean and synchronized with `origin/main`.
- Commit `a5ea62b` (`Fix WatchConnectivity startup actor crash`) is pushed to `main`.
- The iPhone startup crash from `DOGesTNdwLukUcrEdbndgj.xccrashpoint` was reproduced with a background-queue `WCSessionDelegate` regression test. Before the fix it terminated with `SIGTRAP` in `_dispatch_assert_queue_fail`, matching the supplied crash stack.
- The fix makes iPhone `WCSessionDelegate` entry points `nonisolated` and hops state mutations to `MainActor` in `Cadence/Cadence/App/AppModel.swift`.
- The focused regression test passes repeatedly: `CadenceTests/AppModelWCSessionDelegateTests/testActivationCallbackCanEnterFromWatchConnectivityQueue`.
- `make ci` passed locally: 1,311 SwiftPM tests, test-pyramid guardrail, and no-network guardrail.
- GitHub Actions run 31915732406 passed core tests, archive, warning checks, IPA export, and TestFlight upload.
- The full local UI smoke run was not used as release evidence: it exposed pre-existing accessibility-selector drift and later an Xcode simulator test-runner injection hang. Those unrelated UI-test edits were intentionally excluded from the crash-fix commit.

## Overall plan position

- The v1 iPhone + embedded Watch release is shipped and the iPhone WatchConnectivity startup crash fix is on `main`.
- We are now executing the open field-testing pass, beginning with the Home dashboard presentation and semantics batch.
- This task completed Home dashboard backlog items 1–5 below. The changes are currently uncommitted in the working tree; verify, commit, and push only when the user directs that release workflow.

## Completed in the current field-testing pass

1. **Home hierarchy and width.** `This Week`, `Weekly Volume`, and `Coach’s suggestions` now use the smaller `.headline` hierarchy. Home cards use aligned full-width margins.

2. **Weekly status colors and semantics.** Strength/Cardio labels and progress lines are yellow below target and green at/above target. Volume lines are yellow below starting range, green in the productive range, and red with an explicit recovery warning above range. VoiceOver receives the numeric value and status text.

3. **Weekly Volume copy.** Row prose was removed. `Show more` expands the productive/below-productive explanation and retains the science citation link.

4. **Coach recommendation actions.** The Coach card now says `Workout created to close gaps for this week`, previews the same generated recommendation, and reveals an optional `Start Workout` action for that recommendation.

5. **Regression coverage.** Added presenter tests for below, productive, at-ceiling, above-recovery, and below/at/above-target boundaries.

6. **Coach illustration asset.** Added four vector coach illustrations as Xcode image assets. Home selects one in `@State` once per Home presentation and places it immediately below `Coach’s suggestions`; About and `docs/THIRD_PARTY_NOTICES.md` include VideoPlasty/Wikimedia attribution and the CC BY-SA 4.0 license link.

Verification for this batch:

- `make ci` passed after the dashboard refactor: 1,315 SwiftPM tests, test-pyramid guardrail, and no-network guardrail.
- Final iOS `xcodebuild build` passed after the last label-color adjustment.
- Final test-pyramid and no-network guardrails passed.
- Replacement SVG asset batch verification passed: explicit `xcodebuild -project Cadence/Cadence.xcodeproj -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build`, 1,315 SwiftPM tests, test-pyramid guardrail, and no-network guardrail.
- Final simulator smoke verification passed without bypasses: `make smoke` passed the iPhone WatchConnectivity regression and the complete iPhone launch → plan → log → edit → cancel → end → summary workflow; `make watch-smoke` passed all 3 Watch unit tests and the complete Watch strength-workout UI smoke. The smoke selectors now match the current Quick Start, set-row RPE, visible reps controls, and exercise-edit state contracts.

## Lifecycle reliability batch — implementation complete, device evidence pending

- Root foreground transitions no longer trigger a full SwiftData history fetch and synchronous coach-plan rebuild through `AppModel.pushSettingsContext()`.
- Home publishes its already-computed `WatchSync.TodayPlan` into an in-memory cache after the existing asynchronous coach snapshot task. Foreground/settings Watch sync reuses that cache; an installed Watch receives the refreshed plan without blocking the unlock transition.
- Added `CadenceTests/AppModelWCSessionDelegateTests/testHomePlanUpdateUsesCacheForLaterForegroundSync` alongside the existing background-queue WatchConnectivity delegate regression.
- Focused app test passed: 2 tests, 0 failures. `make ci` passed: 1,315 SwiftPM tests, test-pyramid guardrail, and no-network guardrail.
- A simulator background→foreground probe reached the Home control within the 5-second threshold, but the full UI smoke workflow still hits the previously documented Quick Start/accessibility-selector drift. The current XCTest SDK exposes no simulator lock-button API, so physical lock/unlock timing and an Instruments main-thread trace remain required release evidence.

## Watch startup reliability batch — implementation complete, device evidence pending

- `WatchWorkoutManager`’s `WCSessionDelegate` callbacks are now `nonisolated`, matching the iPhone actor-boundary fix. Property-list payloads and reply handlers cross into `MainActor` through narrowly scoped unchecked bridges; manager state remains actor-isolated.
- Added `Cadence Watch App Watch AppTests/activationCallbackCanEnterFromWatchConnectivityQueue`, which invokes the delegate through `WCSessionDelegate` from a background queue.
- Watch simulator build passed with the watchOS 26.5 SDK, and the full Watch unit-test target passed (3 tests, 0 failures), including the background-queue delegate regression.
- A physical Watch test was attempted on the paired Series 9 but Xcode timed out while waiting for device preparation; it reported that the Watch must be unlocked to recover from a prior preparation error. Physical launch/WatchConnectivity smoke evidence is still pending.

## Next field-testing backlog

### Coach illustration assets

1. **Add a full-width coach illustration.** Place one illustration immediately below the Coach’s Suggestions title and before its text/actions. Four source SVGs are currently in `~/Downloads`:

   - `Coach_Lifting_Dumbbells_Cartoon.svg`
   - `Coach_Using_a_Stopwatch_Cartoon.svg`
   - `Coach_Using_a_Whistle_Cartoon.svg`
   - `Coach_Yelling_Cartoon.svg`

   Preserve them as vector assets, randomly choose one once per Home presentation (not on every SwiftUI redraw), and show it immediately below the section title. Confirm licensing/attribution before release.

### Lifecycle and watch reliability

2. **Investigate unlock touch freeze.** Reproduce the several-second delay after returning from the locked screen, then profile the main thread and foreground lifecycle. Audit foreground-triggered settings sync, SwiftData/HealthKit work, coach snapshot recomputation, and any synchronous initialization. The fix must make the first Home interaction responsive immediately after unlock and include a lock/unlock regression scenario.

3. **Watch startup auto-close.** The actor-boundary fix and background-queue regression test are complete; physical launch/crash capture, WatchConnectivity activation, and clean-start smoke evidence remain pending until the paired Watch can be unlocked and prepared.

## Immediate next task

Run the physical-device lock/unlock pass with Instruments: capture unlock-to-first-touch timing and a main-thread trace, then verify that HealthKit, SwiftData/CloudKit, and the asynchronous coach snapshot do not add a second foreground stall. After the paired Watch is unlocked, run its physical launch/WatchConnectivity smoke pass and capture the startup result.

### Lifecycle batch investigation (2026-08-15)

- Initial code audit found that `RootTabView` calls `AppModel.pushSettingsContext()` synchronously on every `.active` transition. When a Watch is available, that path fetches SwiftData history and recomputes the complete coach plan before returning to the run loop.
- Home HealthKit reads suspend at async query boundaries; Home's coach snapshot already moves pure computation to a detached task, although SwiftData value extraction remains on the main actor.
- Intended first fix: make foreground Watch settings sync lightweight and publish the already-computed Home plan asynchronously/cached, then add regression coverage for the foreground transition not doing the expensive plan rebuild inline.
- Implementation is complete as described above. Remaining field work is physical-device lock/unlock profiling and confirmation that HealthKit/SwiftData/CloudKit activity does not introduce a second stall.

### Superseded GIF asset finding (2026-08-15)

- The previously inspected five GIFs were opaque 854×480 VideoPlasty previews with a watermark and are not part of this implementation.

### Current SVG license finding (2026-08-15)

- The four replacement SVGs match the Wikimedia Commons coach illustration records and contain 16:9 1920×1080 view boxes.
- The source records identify VideoPlasty as author and CC BY-SA 4.0 as the license. The app must retain attribution and the license link; the files should not be labeled CC0 without a separate rights confirmation.

## Acceptance criteria for the next field-testing pass

- Home headings visually match the `What you did` hierarchy and all cards share aligned margins.
- Strength/Cardio and volume status colors are correct at below, in-range, at-target, and over-range boundaries and remain accessible without color.
- Coach recommendation copy is clear; Preview and optional Start actions operate on the same generated workout.
- Every Coach card presentation includes one full-width coach illustration without blocking Home interaction or causing repeated asset reloads.
- Unlock-to-first-touch is responsive with no multi-second main-thread stall.
- Watch app launches reliably, remains open, activates WatchConnectivity, and passes the watch unit/UI smoke suite.
- Existing iPhone crash regression, SwiftPM tests, guardrails, archive, and TestFlight checks remain green.
