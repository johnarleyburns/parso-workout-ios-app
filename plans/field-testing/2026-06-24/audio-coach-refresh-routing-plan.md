# Audio, Coach Freshness, And Coach Start Routing Plan

**Date:** 2026-06-24  
**Stream:** `plans/field-testing/2026-06-24/`  
**Scope:** Fix workout cue audio interference, stale Coach/This Week data after cardio completion, wrong "Why this today" recency facts, and Coach Start routing that bypasses workout setup screens.

## Product Goal

Cladiron must never pause or lower unrelated background audio. Completing a workout must immediately update Home, This Week, Coach's recommendation, and "Why this today" without requiring app re-entry. Starting any Coach-recommended workout must land on that workout's setup/settings surface first, never directly into an active recorder.

## Reported Problems Mapped To Work

| User report | Workstream |
|---|---|
| 1. Warm-up pauses background audio | A. Non-interrupting audio session |
| 2. Exercise lowers background audio volume | A. Non-interrupting audio session |
| 3. "Why this today" shows last strength/cardio from last week, missing yesterday | B. Coach fact ordering and last-event selection |
| 4. Cardio completion does not immediately update This Week | C. Post-save Home refresh |
| 5. Cardio completion does not immediately update Coach recommendation | C. Post-save Home refresh plus B ordering |
| 6. After cardio completion, "Why this today" still shows old last cardio | C. Post-save Home refresh plus B ordering |
| 7. Coach "Boxing conditioning" starts generic Other cardio | D. Coach launch routing |
| 8. Coach Start should always open setup first | D. Coach launch routing |

## Current Code Map

Primary files:

- `Cadence/Cadence/Shared/WorkoutCues.swift`
  - `WorkoutCues.transition` sets `AVAudioSession.Category.playback` with `.duckOthers` and `.mixWithOthers`.
  - `startBeepSequence` and `endBeepSequence` use `AudioServicesPlaySystemSound`.
  - Comments still say other audio is ducked.
- `Cadence/Cadence/Shared/IntervalCues.swift`
  - `activateSession` sets `.playback` with `.duckOthers`.
  - `deactivate` calls `.notifyOthersOnDeactivation`.
  - Boxing bells and spoken cues use this path.
- `Cadence/Cadence/Features/Shared/GuidedPhaseOverlay.swift`
  - Warm-up/cool-down overlays trigger `WorkoutCues.startBeepSequence`.
- `Cadence/Cadence/Features/Home/HomeView.swift`
  - `@Query` arrays drive `coachDecision`, `thisWeekCard`, `recentItems`.
  - `buildTrainingEvents` concatenates strength events, then cardio events, then assessments.
  - `coachDayToken` is written but not read.
  - Cardio presentation call sites do not pass an `onSaved` refresh callback:
    - `RecordCardioView`
    - `OutdoorCardioView`
    - `IntervalView`
    - `SwimRecordView`
  - `launchDecision` maps Coach cardio directly to recorder state and misses `"boxing"`, causing fallback to `.other`.
- `Cadence/Cadence/Features/Cardio/RecordCardioView.swift`
- `Cadence/Cadence/Features/Cardio/OutdoorCardioView.swift`
- `Cadence/Cadence/Features/Intervals/IntervalView.swift`
- `Cadence/Cadence/Features/Cardio/SwimRecordView.swift`
  - Each save path persists cardio and shows a summary, but does not notify Home.
- `CadenceCore/Sources/CadenceCore/CoachFacts.swift`
  - `completed`, rolling windows, and weekly events preserve caller input order.
  - Rolling filters do not explicitly exclude future events.
- `CadenceCore/Sources/CadenceCore/CoachDecision.swift`
  - Observed facts use `.last(where:)` over `rolling72hCompletedEvents`.
  - This is only correct if the rolling array is chronological.
- `Cadence/Cadence/Features/Coach/CoachDecisionCardView.swift`
  - CTA label says `"Start cardio"` for moderate aerobic.
- `CadenceCore/Sources/CadenceCore/CoachSession.swift`
  - `aerobic.moderateBoxing` uses `launchPayload: .cardio(type: "boxing", durationMinutes: 25)`.
  - Its `modality` is `.other`, which is lossy for future preference/routing work.

## Non-Goals

- Do not disable workout sounds globally to hide the bug.
- Do not remove haptics.
- Do not change moderate-equivalent minute math; user confirmed it is currently correct.
- Do not make Coach open an active workout directly from the card, even if the target has no configurable options today.
- Do not introduce server state, telemetry, or an LLM.

## A. Non-Interrupting Audio Session

### A1. Add A Single Audio Policy Helper

Create `Cadence/Cadence/Shared/WorkoutAudioSession.swift`.

Required behavior:

- Configure all Cladiron workout cues to mix with other audio.
- Never request `.duckOthers`.
- Never use an audio category/mode combination that pauses background audio.
- Keep the implementation centralized so future cue code cannot reintroduce ducking.

Suggested API:

```swift
@MainActor
enum WorkoutAudioSession {
    static func configureForCues() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
    }
}
```

If product wants cue sounds to ignore the silent switch later, use `.playback` only with `.mixWithOthers` and no `.duckOthers`; validate that it still does not pause background audio. Prefer `.ambient` for this fix because the user's priority is non-interference.

### A2. Route All Cue Audio Through The Helper

Update:

- `WorkoutCues.transition`
- `WorkoutCues.startBeepSequence`
- `WorkoutCues.endBeepSequence`
- `IntervalCues.activateSession`
- `IntervalCues.warning`
- `IntervalCues.completed`
- `IntervalCues.speak`

Rules:

- Remove `.duckOthers` everywhere.
- Remove comments that describe ducking as desired behavior.
- Avoid repeated category churn during every interval phase. Configure once when cues begin or before the first cue.
- Prefer not to call `setActive(false, options: .notifyOthersOnDeactivation)` for normal phase transitions. If deactivation remains at interval end, do not rely on it to repair an interruption; there should be no interruption in the first place.

### A3. Be Careful With System Sounds

`AudioServicesPlaySystemSound` may follow the app's current audio session behavior. Call `WorkoutAudioSession.configureForCues()` before system beeps. If testing still shows pauses or ducking, replace system sounds with a tiny app-owned beep player using `AVAudioPlayer` or `AVAudioEngine` under the same non-interrupting session helper.

### A4. Audio Acceptance Criteria

Manual device test with Apple Music/Spotify/Podcast already playing:

1. Start strength with warm-up enabled.
2. Start indoor cardio.
3. Start outdoor run/walk/cycle.
4. Start boxing intervals and hit phase transitions plus 30-second warning.
5. Start HIIT with spoken cues on.

Pass condition: background audio continues and volume does not drop for every case.

Regression checks:

- Add a small app-unit test around a pure `WorkoutAudioSession.Configuration` value if direct `AVAudioSession` inspection is awkward.
- Add a CI/script check or documented pre-merge check:
  - `rg -n "duckOthers|setCategory\\(\\.playback" Cadence/Cadence`
  - Any remaining result must be intentionally justified and must still mix without ducking.

## B. Coach Fact Ordering And Last-Event Selection

### B1. Make `CoachFacts` Chronological And Future-Safe

In `CadenceCore/Sources/CadenceCore/CoachFacts.swift`:

- Build `completed` as completed events with `end <= now`.
- Sort `completed` by `end` ascending so newest is last.
- Build rolling windows from the sorted list and keep them sorted.
- Filter windows with explicit lower and upper bounds:
  - 72h: `event.end >= now - 72h && event.end <= now`
  - 7d: `event.end >= now - 7d && event.end <= now`
  - 28d: `event.end >= now - 28d && event.end <= now`
- Build `thisWeek` with `start >= thisWeekStart && start <= now`.

This makes downstream code deterministic regardless of whether Home supplies events as strength-first, cardio-first, newest-first, or oldest-first.

### B2. Make Observed Facts Robust Anyway

In `CadenceCore/Sources/CadenceCore/CoachDecision.swift`:

- Replace `.last(where: { $0.isStrength })` with a max-by-end helper:
  - `facts.rolling72hCompletedEvents.filter(\.isStrength).max { $0.end < $1.end }`
- Do the same for last cardio.
- Keep the static `value` strings (`"2h ago"`, `"1d ago"`) and do not reintroduce live relative SwiftUI dates.

### B3. Add Failing Tests First

Update `CadenceCore/Tests/CadenceCoreTests/CoachDecisionEngineTests.swift`.

Current `testObservedFactsPickNewestCardioWhenEventsUnsorted` is not actually unsorted because it passes `[older, newer]`. Replace or add tests that fail under the current code:

- `testObservedFactsPickNewestCardioWhenEventsAreNewestFirst`
  - Create `newWalk` ending 1h ago and `oldRun` ending 2d ago.
  - Pass `[newWalk, oldRun]`.
  - Expect detail contains `Walk`.
- `testObservedFactsPickNewestStrengthWhenHomeSuppliesNewestFirst`
  - Create `newBench` yesterday and `oldSquat` last week or 2d ago.
  - Pass `[newBench, oldSquat]`.
  - Expect detail contains `Bench`.
- `testObservedFactsPickNewestForHomeMixedOrdering`
  - Pass events in Home-like order: all strength newest-to-oldest, then all cardio newest-to-oldest.
  - Expect newest strength and newest cardio.
- `testFutureEventsDoNotCountAsLastOrWeeklyBalance`
  - Add one future cardio and one past cardio.
  - Expect last cardio is the past event and weekly balance excludes the future one.

Update `CadenceCore/Tests/CadenceCoreTests/CoachFactsTests.swift`:

- Add a test that `rolling72hCompletedEvents` is sorted ascending by `end`.
- Add a test that this week's balance excludes future events.

### B4. UI Regression Seed

Add a deterministic seed in `Cadence/Cadence/App/UITestSeed.swift`, for example `coachYesterdayMixedHistory`:

- Older strength from previous week.
- Older cardio from previous week.
- Strength yesterday.
- Cardio yesterday.
- Enough aerobic minutes that moderate-equivalent remains obviously correct.

Add or extend `Cadence/CadenceUITests/WhyThisTodayUITests.swift`:

- Launch with `coachYesterdayMixedHistory`.
- Open `Why this today`.
- Assert `whyToday.fact.lastStrength` exists and contains the yesterday strength detail.
- Assert `whyToday.fact.lastCardio` exists and contains the yesterday cardio detail.
- Assert the moderate-equivalent row still shows the expected total.

If current accessibility labels do not expose enough row content, update `WhyThisTodayView.factRow` to set a combined accessibility label.

## C. Post-Save Home Refresh

### C1. Add An Explicit Home History Refresh Path

In `HomeView`, replace the unused `coachDayToken` with a token that is read by computed surfaces:

```swift
@State private var historyRefreshToken = UUID()

private func markWorkoutHistoryChanged() {
    Task { @MainActor in
        await Task.yield()
        historyRefreshToken = UUID()
    }
}
```

Read the token in the surfaces that must recompute:

- `coachDecision`
- `buildTrainingEvents`
- `thisWeekCard`
- `recentItems`

Example:

```swift
private var coachDecision: CoachDecision {
    _ = historyRefreshToken
    ...
}
```

The token should not replace SwiftData queries; it forces SwiftUI to re-enter the computed paths after save notifications have had a main-actor turn to propagate.

### C2. Notify Home From Every Cardio Save Path

Add an optional `onSaved` callback to:

- `RecordCardioView`
- `OutdoorCardioView`
- `IntervalView`
- `SwimRecordView`

Suggested shape:

```swift
var onSaved: (CardioWorkout) -> Void = { _ in }
```

Call it immediately after `WorkoutRepository.saveRecordedCardio` or `saveSwim` succeeds and before dismissing or after setting `finishedSummary`.

Update Home presentation call sites:

- `.sheet(item: $cardioType) { RecordCardioView(..., onSaved: { _ in markWorkoutHistoryChanged() }) }`
- `.fullScreenCover(item: $outdoorType) { OutdoorCardioView(..., onSaved: { _ in markWorkoutHistoryChanged() }) }`
- `.fullScreenCover(item: $intervalLaunch) { IntervalView(..., onSaved: { _ in markWorkoutHistoryChanged() }) }`
- `.fullScreenCover(isPresented: $swimPresented) { SwimRecordView(onSaved: { _ in markWorkoutHistoryChanged() }) }`

Also pass `onSaved` into:

- `LogWorkoutPicker(onSaved: markWorkoutHistoryChanged)` in Home.
- `syncCardioFromHealth`: have `WorkoutRepository.ingest` return the inserted count and call `markWorkoutHistoryChanged()` when count > 0.
- Cardio delete/restore paths if Home remains visible.

### C3. Make Summary Dismissal Reveal Fresh Home

For live cardio and intervals:

- Save local SwiftData first.
- Call `onSaved(saved)`.
- Set `finishedSummary`.
- When the user taps Done and the cover dismisses, Home should already show:
  - updated `home.cardioMinutes`
  - updated Coach card
  - updated `Why this today`
  - updated recent workout row

Do not wait for `scenePhase == .active`; that is exactly why the bug appears fixed only after app re-entry.

### C4. Tests For Refresh

Add UI tests where feasible:

- `testLoggedCardioImmediatelyRefreshesHomeAndWhyToday`
  - Start from a seed with known `home.cardioMinutes`.
  - Use Log Workout to add cardio yesterday/today.
  - Assert `home.cardioMinutes` changes without relaunch.
  - Open `Why this today` and assert last cardio matches the saved workout.
- `testLiveCardioSaveNotifiesHome`
  - If live duration is too short to change integer minutes, add a test-only fast-duration injection or assert recent workout plus Coach last-cardio fact instead of minute total.

Add manual QA for a real live cardio session:

1. Note This Week moderate-equivalent minutes and Coach card.
2. Complete cardio.
3. Tap Done on summary.
4. Without backgrounding or re-entering the app, verify This Week, Coach card, and Why This Today are updated.

## D. Coach Launch Routing

### D1. Change Coach CTA Copy

In `Cadence/Cadence/Features/Coach/CoachDecisionCardView.swift`:

- For trainable Coach recommendations, use `"Start"`.
- Specifically change `.moderateAerobic` from `"Start cardio"` to `"Start"`.
- Keep rest/recovery wording only if it is intentionally not a workout launch.

Suggested:

```swift
private var ctaLabel: String {
    switch decision.primary.kind {
    case .rest: return "Take a rest day"
    case .recovery: return "Start recovery"
    default: return "Start"
    }
}
```

### D2. Do Not Set Recorder State Directly From Coach

In `HomeView.launchDecision`, replace direct assignments to `cardioType` with routing through the same setup surfaces used by the normal Cardio path.

Required mapping:

| Coach payload | Expected Coach Start destination |
|---|---|
| `.strengthPlan` | `WorkoutPlanEditor` with the Coach plan |
| `"run"` | `CardioGoalSheet` for run, then HR gate, then `OutdoorCardioView` only after the user taps Start |
| `"walk"` | `CardioGoalSheet` for walk |
| `"cycle"` | `CardioGoalSheet` for cycle |
| `"swim"` | `SwimRecordView` setup screen |
| `"hiit"` | `IntervalSetupView(type: .hiit)` |
| `"boxing"` | `IntervalSetupView(type: .boxing)` |
| `"rowing"` | A setup screen first, not immediate recording |
| unknown/other | Other Cardio entry or timer-cardio setup first |

Immediate fixes:

```swift
case "boxing":
    intervalType = .boxing
case "hiit":
    intervalType = .hiit
case "run":
    startOutdoorWithGoal(.run)
case "walk":
    startOutdoorWithGoal(.walk)
case "cycle":
    startOutdoorWithGoal(.cycle)
case "swim":
    swimPresented = true
case "rowing":
    timerCardioSetup = TimerCardioSetup(type: .rowing, suggestedMinutes: duration)
default:
    otherCardioEntryPresented = true
```

The `timerCardioSetup` piece does not exist yet. Add a small setup view rather than sending rowing/other straight into `RecordCardioView(initialType:)`.

### D3. Add A Timer Cardio Setup Surface

Create a compact setup screen for non-GPS timer workouts such as rowing and other indoor cardio.

Suggested file:

- `Cadence/Cadence/Features/Cardio/TimerCardioSetupView.swift`

Behavior:

- Shows the target type, suggested duration from Coach when present, and HR monitoring toggle.
- Optional duration goal can be read-only copy for now; no need to enforce auto-stop.
- Has a single `"Start"` button.
- Only after tapping Start does it set `cardioType` and open `RecordCardioView(initialType:)`.

This closes the "all Coach workouts go to settings first" requirement for non-GPS cardio.

### D4. Preserve Coach-Specific Intent

Consider extending `CoachSession.AerobicModality` with `.boxing` instead of representing boxing as `.other`. This is not strictly required to fix launch routing because `launchPayload` already says `"boxing"`, but it prevents future preference learning and UI copy from conflating boxing with generic Other cardio.

If changing the enum:

- Update Codable/export tests if needed.
- Update `CoachPreferenceProfile` tests.
- Update `CoachSession.candidates` so `aerobic.moderateBoxing.modality == .boxing`.

### D5. Coach Launch Tests

Add UI seeds in `UITestSeed.swift`:

- `coachBoxingPrimary`
  - Make Coach primary be `Boxing conditioning`. Current scoring may already choose this on aerobic need because the ID sorts early, but make the seed deterministic.
- `coachRunPrimary`
- `coachStrengthPrimary`

Add UI tests:

- `testCoachBoxingStartOpensBoxingSetup`
  - Launch with `coachBoxingPrimary`.
  - Assert Coach card title contains `Boxing conditioning`.
  - Assert CTA label is `Start`.
  - Tap `home.coachStart` or `coach.card.state`.
  - Assert `interval.custom.rounds` or navigation title `Boxing` exists.
  - Assert `record.elapsed` does not exist.
  - Assert `interval.countdown` does not exist until tapping `interval.start`.
- `testCoachRunStartOpensGoalSetup`
  - Tap Coach Start.
  - Assert `goal.none` exists.
  - Assert outdoor elapsed does not exist until tapping a goal/no-goal start.
- `testCoachStrengthStartOpensWorkoutPlanEditor`
  - Tap Coach Start.
  - Assert `editor.start` exists.
  - Assert no active `session.elapsed` or set logging UI until tapping editor Start.

Update existing `P5DoThisUITests` if it still expects Coach Start to materialize an active session immediately. The new contract is setup first.

## Execution Order

1. Add failing tests for B and D first.
2. Implement B ordering fixes in `CoachFacts` and `CoachDecision`.
3. Implement C refresh callbacks and Home token invalidation.
4. Implement D Coach routing and CTA copy.
5. Implement A audio policy helper and remove all ducking.
6. Run core tests.
7. Run targeted UI tests.
8. Perform manual device audio verification.

## Verification Commands

Core package:

```sh
swift test
```

Targeted UI tests will likely use Xcode schemes. Run at least:

```sh
xcodebuild test -project Cadence/Cadence.xcodeproj -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CadenceUITests/WhyThisTodayUITests
xcodebuild test -project Cadence/Cadence.xcodeproj -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CadenceUITests/P5DoThisUITests
```

Audio grep:

```sh
rg -n "duckOthers|setCategory\\(\\.playback" Cadence/Cadence
```

Expected after the fix: no `.duckOthers`. Any `.playback` use must be explicitly reviewed for mix-without-duck behavior.

## Final Acceptance Checklist

- [ ] Warm-up cues do not pause background audio.
- [ ] Workout/interval cues do not lower background audio volume.
- [ ] `Why this today` last strength uses the most recent completed strength event by end date.
- [ ] `Why this today` last cardio uses the most recent completed cardio/interval event by end date.
- [ ] Moderate-equivalent minutes remain correct.
- [ ] Completing cardio updates This Week without app re-entry.
- [ ] Completing cardio updates Coach recommendation without app re-entry.
- [ ] Completing cardio updates `Why this today` without app re-entry.
- [ ] Coach CTA says `Start` for cardio recommendations.
- [ ] Coach Boxing opens Boxing interval setup, not generic Other cardio.
- [ ] Every Coach workout Start opens setup/settings first.
- [ ] No active workout UI appears from a Coach Start until the user confirms from the setup surface.
