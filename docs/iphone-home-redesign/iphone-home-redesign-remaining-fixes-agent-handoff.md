# iPhone Home redesign — remaining fixes implementation handoff

Date audited: 2026-08-15

This document is an implementation task list, not a design discussion. It is a delta from `iphone-home-redesign-agent-handoff.md`, which remains the source of truth. Read that handoff and every HTML mockup in this directory before editing code.

## Current verification baseline

The repository currently builds and its package tests pass:

- `swift test --package-path CadenceCore`: 1,322 tests, 0 failures.
- `xcodebuild -project Cadence/Cadence.xcodeproj -scheme Cadence -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' CODE_SIGNING_ALLOWED=NO build`: succeeded.
- `git diff --check`: succeeded.

Those results prove compilation and existing regression coverage only. They do not satisfy the mandatory exit matrix. Do not report this feature complete until every unresolved item below and every applicable exit-evidence row is complete.

## Confirmed implemented — preserve these behaviors

Do not undo or duplicate the following:

1. Root tabs are Home, Plan, Tests, Progress in the requested order.
2. Home's visible normal order is Resume when present, Start/Log, This Week, Weekly Volume, Coach's suggestions, What you did.
3. `SelectWorkoutView` exists and directly routes Quick Start and Coach's Workout to `WorkoutPlanEditor`; cardio choices remain present.
4. Strength summary data carries optional `sourceExerciseID` and the just-finished root summary has a source session.
5. Exercise cards can render collapsed or expanded, with a compact summary.
6. The set editor always renders a performer control and the normal/accessibility weight grids use four/two equal flexible columns with label frames before button styling.
7. `IntervalSignal.warningDuration`, duration-aware runner color state, and phone/Watch cue call sites exist.
8. Watch BPM messages include the active request ID, and stale request IDs are rejected by the phone relay.
9. Watch store creation no longer terminates with `fatalError`.

## Required implementation order

Implement in this order so later UI work is built on valid state rather than patched around it:

1. Pure Home dashboard/suggestion presenter and free-Coach cleanup.
2. Atomic live-workout coordinator plus value-typed start intents and recorder lifecycle ownership.
3. Testable Watch store bootstrap policy.
4. Complete Watch-HR request/readiness/cleanup state machine.
5. Stable set-editor context, activity relay, and performer picker flow.
6. Pure accordion transitions and complete summary-focus navigation.
7. Missing interval contract tests.
8. UI, accessibility, Watch, and physical-device exit evidence.

After each numbered phase, run the relevant focused tests. After all phases, run the full verification commands in the final section.

---

## FIX-01 — Home must use a pure dashboard presenter

### Current incorrect state

- There is no `HomeDashboardPresenter` or `HomeDashboardState` in `CadenceFeatures`.
- `HomeView.weekDashboardSection` calculates target values directly from `coachDecision` and settings.
- `HomeView.weeklyVolumeSection` calculates bands and zones directly in the SwiftUI body.
- `HomeView.coachSuggestionsSection` sets `items = coachInsights`. This does not merge weekly deficits, test recommendations, readiness/safety, volume/recovery, and progress observations, and it does not de-duplicate equivalent claims.
- Home volume rows show only set counts, not the textual range state required for zero and nonzero rows.
- Weekly Volume still renders in `TrainingProgressView` as `volumeCard`.

### Exact implementation

1. Add `HomeDashboardPresenter` and its plain value types under `CadenceCore/Sources/CadenceFeatures/`. Keep each file under the repository's 400-line limit.
2. The presenter output must include exactly:
   - `profileContext` with goal, experience, and honest age text (`Age not set` when missing);
   - strength completed distinct days, target days, display text, and normalized progress;
   - cardio moderate-equivalent minutes, 150-minute target, display text, and normalized progress;
   - exactly eight volume rows in `BodyPart.allCases` order, including zeros;
   - `.abs` display name `Core` only in this Home presenter;
   - every row's set count, band/range status text, normalized bar value, and citation ID;
   - a ranked, de-duplicated `[HomeSuggestion]`.
3. Build suggestions from all available snapshot inputs, not `coachSnapshot.insights` alone. Assign deterministic categories in this exact order:
   1. safety/pain/readiness;
   2. current-week strength/cardio deficit;
   3. muscle-volume/recovery gap;
   4. plan/test action;
   5. progress observation.
4. Within a category preserve existing priority, confidence, then stable ID ordering. Define one stable de-duplication key per underlying claim. Equivalent weekly-deficit/volume claims must collapse to one suggestion. Do not de-duplicate only by visible title.
5. Do not fabricate a suggestion when all sources are empty.
6. Make `HomeView` render only prepared dashboard values. SwiftUI may map semantic statuses to colors, but it must not calculate training facts, ranges, ordering, or de-duplication.
7. Remove `volumeCard` from `TrainingProgressView`'s render order. Remove the dead private card code if no other caller uses it. Do not remove the other Progress cards.
8. Keep all visible scientific claims linked through `CitationLink`; never expose a raw citation ID.

### Required tests

Add `HomeDashboardPresenterTests` covering all Home-dashboard test cases in the source handoff: eight ordered rows including zero, Core naming, distinct strength days, age-aware supplied cardio facts, missing age, deleted/future exclusion through supplied facts, deterministic suggestion ordering, de-duplication, citation preservation, and empty output.

### Acceptance check

`rg -n 'let items = coachInsights|VolumeLandmarks\.bands|VolumeLandmarks\.zone' Cadence/Cadence/Features/Home/HomeView.swift` must return no Home dashboard calculations.

---

## FIX-02 — remove the old standard-tier Coach gate completely

### Current incorrect state

The old gate remains in production code even though some of it is no longer in the visible Home stack:

- `HomeView` still owns `coachSurfaceState`, `coachShowsUnlockCTA`, `coachTopSurface`, `coachAmbientSurface`, `showPaywall`, trial UI, `.coachPreview`, and `.planning` routes.
- `HomeView` still presents `PaywallView`.
- `OnboardingView` still imports Store state, owns `showPaywall`, and defines a Coach paywall sheet.
- `HomeCoachModel.upsellCTAVisible`, `CoachUpsellPolicy`, `CoachSurfacePresenter`, preview screens, and their obsolete tests remain.

Dead or currently unreachable gating is still incomplete migration. Remove it; do not leave it for a future caller to reactivate.

### Exact implementation

1. Remove from `HomeView`:
   - `StoreService` dependency if no longer needed for contribution/store functionality;
   - `showPaywall`;
   - `coachSurfaceState`;
   - `coachShowsUnlockCTA`;
   - `coachTopSurface`;
   - `coachAmbientSurface`;
   - trial-banner UI used only by the old Coach gate;
   - `.coachPreview` and `.planning` navigation destinations and every caller.
2. Keep the functional Coach destinations needed by suggestions, Coach settings, methodology, and plan editing. Do not replace them with a paywall.
3. Remove the paywall state/sheet and unused Store dependency from `OnboardingView`. All completion paths must call `finish()` directly.
4. Remove reachable `CoachPreviewView`/`CoachPreviewScreen` calls. If no production caller remains, delete those source files from the Xcode target and filesystem.
5. Remove `HomeCoachModel.upsellCTAVisible`, `CoachUpsellPolicy`, and entitlement-driven `CoachSurfacePresenter` once no production caller remains. Delete only their obsolete tests at the same time.
6. Preserve StoreKit transaction, restore, product ID, entitlement persistence, and future Trainer infrastructure. Do not invent Trainer UI or new paywall copy.
7. Under `.free`, `.trial`, and `.pro`, dashboard suggestions, Coach's Workout, suggestion actions, and plan editing must be behaviorally identical.

### Required tests

Add a focused free-tier test proving recommendation data and actions are not changed or redirected by entitlement. Add/adjust UI smoke coverage so Coach's Workout opens an editable plan under forced free entitlement without any paywall.

### Acceptance check

These searches must return no standard-tier gate callers:

```sh
rg -n 'coachSurfaceState|coachShowsUnlockCTA|showPaywall|coachPreview|CoachUpsellPolicy|CoachSurfacePresenter' Cadence/Cadence/Features/Home Cadence/Cadence/Features/Onboarding CadenceCore/Sources/CadenceFeatures
```

References inside intentionally retained future StoreKit infrastructure are acceptable; Home/Onboarding/standard Coach logic is not.

---

## FIX-03 — make one-live-workout ownership atomic and route-complete

### Current incorrect state

`LiveWorkoutCoordinator` is only a passive descriptor slot:

- `pending` is only `LiveWorkoutKind`, not a value-typed pending start intent with a commit action/route payload.
- `requestStart` and `acquire` are separate calls, so callers can check, materialize/start work, and race acquisition.
- Most production callers do not call `requestStart` at all.
- Home strength paths create or reuse a `WorkoutSession` before `startStrength` acquires the lease.
- Plan and History conflict paths silently return instead of showing the common conflict and preserving an intent.
- `BodyPartQuickStartView` bypasses the coordinator.
- Coach add-on destinations can open swim/timer/interval setup without going through the same request API.
- Timer-cardio setup is not consistently leased and does not have `onDismiss: releaseCardioWorkout`.
- `releaseCardioWorkout()` releases any active non-strength descriptor without matching the recorder's lease token.
- The conflict UI has no retained exact intent to continue after a final-boundary race.
- The destructive copy says the strength workout "cannot be undone," contradicting the required soft-delete/restore behavior.
- Active cardio conflict offers no Resume or modality-specific cleanup path.

### Exact implementation

1. Replace the current coordinator API with one atomic `requestStart(intent:)` operation. The intent must be a value type containing:
   - a stable request ID;
   - the requested `LiveWorkoutKind` or pre-start route kind;
   - enough immutable payload to resume the exact requested route after cleanup;
   - origin (`homeStart`, final commit, Plan, History reuse, Coach/add-on, etc.) so cancellation returns focus correctly.
2. The coordinator must atomically return either:
   - a lease/token owned by that exact request; or
   - `.conflict(active:descriptor, pending:intent)` without invoking creation/start work.
3. A lease must have stable identity. `release`, `saveComplete`, and `discardComplete` must require the matching token and be idempotent. Never release "whatever happens to be active."
4. Put one final commit API around strength creation/reuse and cardio sensor/timer start. Do not create a `WorkoutSession`, start location, HealthKit, a timer, or provisional Watch HR until the commit owns a lease.
5. Route every live entry through that API:
   - Home Start and all Select Workout strength/cardio choices;
   - Quick Start, Coach's Workout, Previous;
   - Plan/routine editor;
   - History reuse;
   - `BodyPartQuickStartView`;
   - run/walk/cycle, timer cardio, swim, HIIT, boxing, Other Cardio;
   - Coach add-ons and alternatives.
6. Manual historical Log Workout must remain outside the live coordinator.
7. The common conflict UI must render for every origin and retain the exact pending intent. Required actions:
   - `Resume <name>`: clear pending once and present/resume the active modality without changing its clock/data;
   - `Cancel Previous Workout…`: second confirmation; strength copy says it can be restored from deleted History; cardio calls that recorder's idempotent stop/discard and retains the lease if cleanup fails;
   - `Not Now`: clear pending and leave active state unchanged.
8. On successful confirmed cleanup, execute the retained pending intent exactly once. Repeated Resume/Cancel taps and two same-runloop starts must not duplicate cleanup, creation, or presentation.
9. Strength recovery must atomically adopt its lease. If adoption collides with an existing lease, do not overwrite either identity.
10. Recorder owners—not Home presentation-state `onDismiss` handlers—must explicitly finish/discard their matching lease after sensors/timers stop. Dismissing setup before sensors start cancels the reserved intent/lease safely; dismissing an active recorder must complete cleanup before release.

### Required tests

Implement the complete FT-02 matrix from the source handoff. The existing two coordinator tests are insufficient. Include all modality combinations, same-runloop double request, creation closure not invoked on conflict, pending Resume/Not Now, strength soft-delete and one-time continuation, failed cardio cleanup, recovery adoption, token-mismatch release, and manual-log non-conflict.

### Required UI identifiers

Add the exact conflict identifiers from the source handoff: dialog, resume, cancelPrevious, keepCurrent/Not Now, and confirmCancel.

---

## FIX-04 — replace the embedded Watch bootstrap with an injectable policy

### Current incorrect state

- `WatchStoreBootstrap` and filesystem/container work remain embedded in `Cadence_Watch_AppApp.swift` and are synchronously constructed by `App.init`.
- Container and filesystem creation are not injectable, so failure paths cannot be unit tested safely.
- Quarantine failure is swallowed with `try?`; a recovery state may point at the temporary directory even when nothing was quarantined.
- Moving three files is not transactional; a mid-move failure can strand a partial set without a typed error.
- There are no structured `Logger` boot-stage events.
- There is no shared schema-version transition applied on Watch.
- Retry is not serialized and exposes no progress state.
- `Sync from iPhone` only calls `bootstrap.retry()`; it does not request application context first.
- `watch.root` is not applied to the normal root.
- There are no bootstrap failure-injection tests.

### Exact implementation

1. Move bootstrap policy out of the `App` file into small Watch/pure-policy files.
2. Inject protocols/closures for:
   - persistent/in-memory container creation;
   - exact store-file discovery/move;
   - starter seeding;
   - clock/UUID directory naming;
   - schema-version state;
   - structured logging.
3. Model explicit serialized states: idle/opening/quarantining/retrying/ready/recovered/degraded. A second Retry while one is running must be ignored or await the same task.
4. Quarantine only `default.store`, `default.store-shm`, and `default.store-wal` into one unique Application Support recovery directory. Never overwrite or delete an older recovery. If any move fails, return a typed bootstrap error and do not claim recovery succeeded.
5. Seed only the selected usable container and only after creation succeeds.
6. Add the shared schema compatibility/version constant in `CadenceCore` store code and use the same transition policy on iPhone and Watch.
7. Add privacy-safe `Logger` events for initial open, quarantine start/result, persistent retry result, in-memory result, seed result, root visible, and recovery visible.
8. The normal root must expose `watch.root` and must not show an interstitial.
9. Recovery Retry must show progress. Sync from iPhone must ask `WatchWorkoutManager`/WCSession for current application context, wait for response/failure, then retry the persistent store. Copy must state that iPhone data is unaffected and must not promise recovery of unsynced corrupt Watch workouts.
10. Keep the recovery surface usable when the phone is unreachable.

### Required tests

Implement every FT-01 bootstrap policy test listed in the source handoff using temporary/double-backed storage only. Tests must never touch the developer's real Application Support directory.

---

## FIX-05 — complete Watch-HR readiness and cleanup semantics

### Current incorrect state

- The gate introduction still mentions only a Bluetooth chest strap.
- Watch UI is omitted entirely when unavailable, so "Watch app not installed" cannot be distinguished from reachability or permission errors.
- The primary button falls back to an enabled `Continue without heart rate` while Watch is connecting/waiting; it is not disabled with Connecting/Waiting copy.
- A second duplicate "Continue without heart rate" button is always shown.
- Live UI lacks an explicit LIVE badge, source copy, and last-received freshness.
- A stale live state only changes text; it does not transition to action-required/retry.
- Selecting Bluetooth does not stop an active provisional Watch Health session.
- Gate dismissal/cancel, Continue without HR, timeout abandonment, recorder save, and recorder discard do not share one idempotent cleanup owner.
- Home calls `startWatchWorkout` a second time after a fresh Watch sample, violating stream preservation.
- The Watch acknowledgement returns accepted immediately after dispatching `startWorkout`, before Health authorization/session readiness. Authorization failure is never returned as a typed rejection.
- The relay's `receive` method accepts a nil request ID, even though production samples are required to be tagged.
- Stop/request identity is not tracked, so an old stop can affect a newer request.

### Exact implementation

1. Make request ID mandatory for every received Watch sample in production and in the relay API.
2. Define a structured Watch reply with request ID plus `accepted` or typed rejection (`healthPermissionDenied`, `sessionStartFailed`, `alreadyActive`, `unsupported`, etc.). Do not acknowledge accepted until Health authorization and workout/session startup have succeeded enough to produce samples.
3. Track one provisional Watch request owner on iPhone and Watch. Start, stop, timeout, source switch, and late callbacks must all compare request identity.
4. Selecting Apple Watch expands status but does not leave the gate. The primary action states must be exact:
   - before command: Check for Live HR;
   - connecting: Connecting… disabled;
   - acknowledged/no sample: Waiting for Watch HR… disabled;
   - fresh sample: Continue with Apple Watch enabled;
   - stale/error: Retry enabled with an actionable inline reason.
5. Render current BPM, LIVE text, `from Apple Watch`, and last-received freshness. Accessibility must announce source, BPM, and freshness without depending on color.
6. Always represent Watch unavailable/not installed/reachability/Health rejection separately enough to give a next action.
7. Remove the second `startWatchWorkout` call from Home's `onContinue(.watch)`. Continue must preserve the existing request and stream through countdown/recorder.
8. Source switching rules:
   - selecting/connecting Bluetooth stops the provisional Watch request once and waits for a real BLE sample;
   - Continue without HR stops Watch once, disconnects/cleans provisional BLE as appropriate, sets source `.none`, and continues;
   - gate cancellation does the same cleanup without starting a workout.
9. Recorder save/discard and interval/strength completion must stop only the matching Watch request once. Bluetooth must remain usable after Watch cleanup.
10. Readiness samples received before the workout clock starts must not be persisted as in-workout samples. Start workout sampling eligibility at the recorder's clock boundary.

### Required tests

Implement the full FT-03 test matrix. Existing stale/request-ID tests cover only two cases and are not sufficient.

---

## FIX-06 — make Add Partner return to the untouched draft and select the person

### Current incorrect state

- The performer selector is a `Menu`, not the required picker sheet over the editor.
- Add Partner dismisses the full-screen set editor, opens the parent session sheet, then reconstructs the editor.
- Reconstructed config gets a fresh UUID and the draft is recreated, so weight/reps/effort changes can be lost.
- Adding or choosing a person in `addPartnerSheet` does not return/select that person in the current editor draft.
- The roster is snapshotted in immutable `InlineEditorConfig`; the current workaround rebuilds the entire editor to refresh it.
- There is no test for add/reuse/select/cancel behavior on the iPhone editor.

### Exact implementation

1. Keep the full-screen set editor alive. Present a performer picker sheet from inside `InlineSetEditorView`.
2. Keep all weight, reps, effort, bodyweight, and `performerID` fields in one mutable draft model whose identity survives nested performer/Add Partner sheets.
3. Me is first. Then active roster order. Then historically attributed/recent people with context. The edited set's actual person must be present even if no longer active.
4. Add Partner must call case-insensitive `WorkoutRepository.findOrCreatePerson`, append the person ID to `session.activePartnerIDs` at most once, return the `Person`/value to the picker, and immediately select that ID in the existing draft.
5. The roster mutation is immediate and remains if the set editor is cancelled. Draft attribution remains transactional and is written only on Save.
6. Cancel must never update an existing set's stored performer. Save must pass the selected draft ID through existing add/update repository calls without creating a duplicate set.
7. Preserve existing owner PR/Health exclusions and rotation. After Save, `nextPerson()` must rotate from the actual saved performer.

### Required tests

Implement every FT-04 performer test listed in the source handoff. Add UI smoke for solo Add Partner, save/reopen, edit back to Me, and no duplicate set.

---

## FIX-07 — isolate high-frequency set-editor input

### Current incorrect state

- The full-screen cover still calls `inlineEditorConfig()` from live session/query state.
- Add config still creates a fresh UUID.
- Weight/reps/effort taps call parent `onActivity()`, mutating `SessionView`'s observed `@State` watchdog.
- `SessionView` also has a root simultaneous tap gesture, causing duplicate activity delivery.
- Formatting still compiles/runs a regular expression from render helpers.
- Haptic calls still allocate feedback generators per tap.
- There is no `SetEditorContext`, non-render-invalidating activity relay, signpost instrumentation, isolation tests, or physical-device evidence.

### Exact implementation

1. Introduce a stable `SetEditorContext` built once when opening the route. Store it in `@State` before presenting the cover. It must contain stable identity, exercise ID/name, original/editing set ID, history hints, initial roster, initial draft values, and callbacks/value-only dependencies.
2. The cover must render directly from stored context. It must not call repository history lookup, filter query-backed session sets, or create a new UUID during body reevaluation.
3. Draft button actions mutate only the editor draft and prepared haptic object. They must not mutate `SessionView`, SwiftData, render cache, Watch sync, coach state, or run history lookups.
4. Replace per-tap `onActivity` with a reference-type/non-observed activity relay that updates idle liveness promptly and coalesces publication back to session state. Remove the root duplicate simultaneous gesture or make it exclude editor-delivered events.
5. Prepare/reuse haptic generators.
6. Replace regex-based display trimming with a cached formatter or simple deterministic numeric formatter that is not compiled during render.
7. Add `os_signpost` intervals/events for action received, draft committed, body update, context build, history lookup, and Save. Signposts must prove no context/history/persistence/render-cache work between draft taps.
8. Preserve every tap in order and keep Save at-most-once.

### Required tests and evidence

Implement every FT-07 headless test and the ten-tap UI burst. Record release-build median/p95/max on the oldest supported physical iPhone with haptics enabled. Passing simulator behavior does not satisfy this fix.

---

## FIX-08 — complete accordion state transitions and summary drill-in

### Current incorrect state

- Expansion logic is ad hoc in `SessionView`; no pure `SessionExerciseExpansionModel` exists.
- Default active selection chooses the first pending context or first context, not explicitly the first unfinished planned/logged exercise.
- Save closes the editor but does not implement final-planned-set advance versus unplanned-set stay semantics.
- Summary focus changes expansion ID but there is no `ScrollViewReader.scrollTo`, no VoiceOver focus transfer, and no deleted-focus fallback model.
- Review/history navigation creates plain `SessionView` and defaults correctly collapsed, but Home and Progress history summaries do not pass `onExercise`, so rows are non-interactive there.
- Summary row interaction wraps only the exercise name, not the whole minimum-44-point row; there is no trailing chevron and no required footer.
- Compact summary has count/top load only; it does not include useful bodyweight or RPE-range fallback.
- Accordion animation ignores Reduce Motion.

### Exact implementation

1. Add a pure `SessionExerciseExpansionModel` in `CadenceFeatures`. Inputs must be value-only exercise IDs, completed/pending/planned state, route mode, and set-save event kind.
2. Model these transitions exactly:
   - active start: first unfinished exercise, blank => none;
   - review/edit start: none;
   - summary focus: requested existing ID, missing/deleted => none;
   - header tap: one-open toggle with zero-open allowed;
   - opening pending/completed set: owning exercise;
   - non-final planned save: stay;
   - final planned save: next unfinished;
   - unplanned added-set save: stay.
3. Drive `SessionView` state only through this model.
4. Wrap cards in `ScrollViewReader`, assign stable IDs, and scroll after the focused card exists without a fixed delay. Move VoiceOver focus to the expanded exercise heading.
5. Use immediate transitions under Reduce Motion; otherwise use the existing short animation.
6. Make each summary owner/partner exercise roll-up a full-row minimum-44-point button with trailing chevron. Add footer: `Tap an exercise to see every set’s weight, reps, and RPE.`
7. Wire `onExercise` for just-finished, Home history, and Progress history summaries. Use a route carrying both the source session and requested exercise ID so the review expands and scrolls correctly.
8. Improve collapsed actual summary priority: completed/planned count plus top load when meaningful; otherwise bodyweight and/or RPE range. Never truncate numeric set values.

### Required tests

Implement the full accordion state-machine test list and summary identity/navigation tests from the source handoff. Add UI smoke for first/second toggle, finish-summary middle exercise drill-in, actual row visible, and editor open.

---

## FIX-09 — finish interval contract coverage

### Current state

The shared duration-aware formula and call-site propagation are largely implemented. Preserve that code. The remaining issue is proof and one unsafe compatibility path:

- Contractual warning-duration table and epsilon boundaries are not tested.
- Cue tests mostly use the default 180-second parameter rather than explicit durations.
- Extension-to-threshold behavior is not directly tested.
- The compatibility `colorState(phase:remaining:)` overload silently assumes 180 seconds and can reintroduce the old bug for a future caller.

### Exact implementation

1. Add table-driven tests for 20, 30, 45, 60, 90, 120, 180, and 300 seconds.
2. Test work at threshold + epsilon, warning at threshold, and imminent at 3 seconds.
3. Test 20-second and 180-second runner behavior plus effective duration after extension.
4. Test one warning cue at the computed boundary and final-three ticks exactly once.
5. Remove the compatibility overload if no production caller needs it. If a legacy test/helper still needs it, migrate that caller to pass an explicit duration; do not keep a default 180-second production API.

---

## FIX-10 — accessibility identifiers and UI/device exit matrix

### Missing proof

The current UI-test changes mostly rename existing selectors. The mandatory smoke scenarios and device evidence have not been implemented or recorded.

### Exact implementation

1. Add every stable identifier listed in the source handoff. Current known omissions include normal `watch.root`, conflict dialog/actions, expanded-card state, several Watch-HR states, and generic `selectWorkout.previous` for the previous-workout entry.
2. Update the existing smoke suite rather than creating an oversized parallel suite. Implement all 17 iPhone smoke steps in the source handoff.
3. Add Watch clean/relaunch/injected-failure/upgrade smoke coverage.
4. Add deterministic launch arguments/fixtures for free entitlement, active conflict, Watch HR states, interval clock, partner roster, and grid geometry.
5. Record physical evidence exactly as required:
   - paired Watch cold/upgrade launch;
   - paired Watch HR with app initially closed and cleanup after cancel;
   - interval timing on iPhone and Watch;
   - set-editor latency on oldest supported iPhone;
   - grid geometry across required devices/orientations/Dynamic Type.
6. If physical infrastructure is unavailable, mark that exit row `blocked`. Do not call it passed from simulator evidence.

---

## Final verification commands

Run all of these after implementation:

```sh
git diff --check
swift test --package-path CadenceCore
xcodebuild \
  -project Cadence/Cadence.xcodeproj \
  -scheme Cadence \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Do not pass global `-sdk iphonesimulator` to the combined Cadence scheme. Doing so forces the embedded Watch target to use the iPhone SDK and produces misleading Watch asset/WatchKit errors.

Also run the amended iPhone UI smoke suite and Watch tests using the project's normal test plans/destinations. Attach or record paths to every required device artifact.

## Final audit rule

Before reporting completion, re-read the source handoff's Acceptance criteria and Mandatory exit evidence matrix line by line. For each row, record one of:

- `passed` with exact test/log/artifact path;
- `blocked` with the missing physical infrastructure;
- never `assumed`, `covered indirectly`, or `not applicable` when the source handoff requires it.

Compilation plus package tests is not enough to claim this redesign fully implemented.
