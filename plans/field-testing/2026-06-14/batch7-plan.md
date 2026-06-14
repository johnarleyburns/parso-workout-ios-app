# Feedback batch 7 — polish: buttons, haptics, audio cues, guards, defaults

Seventh on-device field-test batch. One PR `feat/ft4b-feedback7`, stacked on #26
(`feat/ft4b-feedback6`). Logic in CadenceCore where it's pure; thin UI on top.
Additive-only schema. Verify (`swift test` + `xcodebuild` + UI), then PAUSE.

## Already landed on this branch (single-line asks from the same session)
- **"top <weight>" → just the weight.** `WorkoutSummaryView.topLabel` drops the
  word "top"; bodyweight rows (`BW` / `BW + X`) unchanged.
- **Quick Start is truly immediate.** `HomeView.launchFromPicker(_:skipCountdown:)`
  — Quick Start bypasses the get-ready countdown regardless of the Settings value
  (library/reuse/warm-up/cardio still honor it). FR7 `testCountdownPause` rerouted
  to launch the countdown via a library preset (`weights.library.preset-5x5-1a`).
  App build green.

## The 10 items

### 1. "Log Workout" save button green (positive action)
`LogCardioView` `log.save`: style as prominent green (match Home "Start Workout").
`.buttonStyle(.borderedProminent).tint(.green)` + large control size. Display-only.

### 3. Direct minute entry in Log (Other) Cardio
`LogCardioView` minutes is a `Stepper` (`log.minutes`). Add a numeric `TextField`
bound to the minutes Int (keep the stepper for nudging, or replace). Keep id
`log.minutes` on the field so FR13 still finds it; numeric keyboard.

### 4. Strength start: Quick Start green/prominent, Start-with-Warm-Up secondary
`WeightsStartView`: pull Quick Start + Start-with-Warm-Up out of the plain List
Section into a styled header. Quick Start = green prominent (Home start style);
"Start with Warm-Up" = quiet secondary (Home "Log Workout" style: tinted/bordered,
lower emphasis). Keep ids `weights.quickStart` / `weights.warmupStart`.

### 5. Allow logging 0 kg (empty bar)
`WeightKeypadSheet.canSave` currently needs weight > 0 for non-bodyweight. Change:
non-bodyweight saves when `reps > 0 && !entry.isEmpty` (an explicit `0` is valid →
saves 0 kg). Empty entry still blocks. Bodyweight path unchanged. PR-preview/format
already handle 0.

### 6. Cool Down confirmation guard
`SessionView` `onCoolDown` runs immediately. Wrap in a `confirmationDialog`:
"Start cool-down? This ends your workout and begins the cool-down timer." →
Confirm (`workout.coolDownConfirm`) / Cancel. New `@State coolDownConfirm`.

### 7. Warm-up / cool-down default 5 min (not 10)
`SettingsDefault.warmupMinutes`/`cooldownMinutes` 10 → 5 (Store.swift). User still
overrides in Settings. **HIIT/boxing are unaffected** — their warm/cool come from
the `IntervalPlan` protocol, not these strength settings; no change there.
(Defaults only apply to users who never set a value; existing saved 10s persist.)

### 8. Auto-end-on-idle on/off toggle
New additive setting `autoEndOnIdle: Bool = true` (key `settings.autoEndOnIdle`).
`SessionView.checkIdle()` no-ops when off. Settings toggle appended at the bottom
of the relevant section (append convention): "Auto-end after idle" with the minutes
stepper shown only when on. Default on = current behavior.

### 9. Warning bell on every phase transition (except boxing)
Today only `IntervalView` plays bells (via `IntervalCues`, bundled
`warning-bell.mp3` / `opening-closing-bell.mp3`). Extend to **all** workouts:
- **Workout start** (strength/cardio/CrossFit): bell when the session begins.
- **start → warm-up → workout → cool-down → end**: bell at each `GuidedPhaseOverlay`
  start/finish and at workout end.
- **HIIT work/rest divisions**: already covered by `IntervalCues.phaseChanged`.
- **Boxing exception**: boxing keeps its own bell cadence — do **not** add a second
  generic bell. (Boxing already routes through `IntervalCues`; ensure no double
  play. If boxing currently uses the same generic bell, that's its "own sound" —
  the requirement is just: don't add a *new* layer for boxing.)
- Master gate: new setting `workoutSounds: Bool = true` (Settings toggle) so the
  whole thing is mutable. Reuse the `IntervalCues` player pattern; extract a tiny
  shared `WorkoutCues.bell()` (or reuse `IntervalCues`) for the strength/cardio
  start/phase/end hooks. No new assets.
- *Open:* confirm boxing's current audio (does it already differ from HIIT?) before
  wiring the exception — see Open questions.

### 2. Light sensory feedback on every tap (Apple HIG)
Add a light selection haptic when the user taps an actionable item — history rows,
start/log type tiles, picker rows, start buttons. Approach: `Haptics.selection()`
(light impact / `.selection` `UISelectionFeedbackGenerator`) called from the tap
handlers, or SwiftUI `.sensoryFeedback(.selection, trigger:)` on row models (iOS 17).
"Everywhere" is broad — cover the primary navigation surfaces (History/Home rows,
Start & Log pickers, session add/record). Document as a convention so new rows adopt
it. (This is the fuzziest item; scope to the main tap surfaces, not literally every
control, in this PR.)

### 10. Apple Health auth resets after each debug install — ANSWER (no code req'd)
Expected behavior, not a bug in Cadence. HealthKit authorization is bound to the
app's install identity + data container. When Xcode does a debug install that
**replaces/deletes** the app (or on the **Simulator**, which resets Health state
readily), iOS revokes the grants and the next launch starts at `notDetermined`.
Also: iOS deliberately **never reports read authorization** (an app can't tell if
read was granted vs denied — privacy), so "connected?" can't be reliably shown.
- On a **real device** with incremental installs (same container, not deleted),
  grants normally persist across rebuilds.
- It resets when you **delete the app**, wipe the container, or run on Simulator.
Optional polish (not required): on launch, if status is `notDetermined`, re-request
authorization so the prompt reappears automatically after a reinstall.

## Build order (low-risk first)
1. **5, 7, 1, 3, 4** — keypad 0 kg, default minutes, three style/field tweaks.
2. **6, 8** — cool-down confirm guard, idle-end toggle.
3. **2** — selection haptics on primary tap surfaces.
4. **9** — audio cues across phases + `workoutSounds` toggle (largest).

## Schema / settings deltas (all additive, defaulted)
- `AppSettings.autoEndOnIdle: Bool = true` (`settings.autoEndOnIdle`).
- `AppSettings.workoutSounds: Bool = true` (`settings.workoutSounds`).
- `SettingsDefault.warmupMinutes`/`cooldownMinutes`: 10 → 5.
- New `Haptics.selection()`; possibly a shared `WorkoutCues` (UI layer only).
- No SwiftData model changes.

## Verify / ship
- `cd CadenceCore && swift test` (149 stay green; default-minutes change has no test
  asserting 10, confirm).
- `cd Cadence && xcodebuild -scheme Cadence -destination 'id=FC7B2F90-…' build`.
- UI: new `FR14Feedback7UITests` — 0 kg set saves; Log minutes typed directly;
  cool-down confirm appears; idle-end toggle present. Regression: FR1/FR7/FR11/FR13.
- Settings rows appended at the bottom (coordinate-tap convention).
- Commit (Co-Authored-By trailer), push, PR stacked on #26. **PAUSE** for on-device
  test (audio/haptics need a real device).

## Open questions (for approval)
- **Item 2 scope**: "everywhere" — OK to cover the main tap surfaces (history/home
  rows, start/log pickers, primary buttons) this PR rather than literally every
  control? (SwiftUI has no global tap hook; per-surface is the practical path.)
- **Item 9 boxing**: confirm boxing's current cues — it already plays the bundled
  bell via `IntervalCues`. Treat "boxing has its own sounds" as "leave boxing as-is,
  don't double-bell", correct?
- **Item 9 default**: ship `workoutSounds` default **on**?
