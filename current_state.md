# Current State — Cadence field-testing redesign

Live handoff/progress tracker.

_Last updated: 2026-06-26 — Coach scheduling (fixed rest days), background interval audio, post-completion add-ons._

## What just shipped — Coach scheduling + audio + add-ons

### Fixed Rest Days
- **`isRestDay(date:restPreference:calendar:)`** in `WeeklyPlan.swift`: `fixed(days:)` short-circuits to `.rest` when the date's weekday is in the configured set; `rolling(everyNDays:)` inserts rest every N days from week start.
- **`futureSessions()`** now accepts `restPreference` and returns `.rest` for fixed rest days before any training check.
- **WhyThisTodayView**: label "Coach will not schedule workouts on selected days." below fixed-day chips.

### Background Interval Audio
- **`audio` added to UIBackgroundModes** in `Info.plist` so cues play when device is locked or app is backgrounded.
- **`WorkoutAudioSession`** switched from `.ambient` to `.playback` with `.mixWithOthers` (no ducking). Added `deactivateSession()` to hand back audio when cues finish.
- **`TonePlayer`** (`Shared/TonePlayer.swift`): `AVAudioEngine`-based sine-wave tone generation replacing `AudioServicesPlaySystemSound` — ticks (1047 Hz, 0.04s) and alerts (1760 Hz, 0.12s) with soft attack/decay envelopes. Shared `countdownStart()` and `rapidEnd()` sequences.
- **`IntervalCues`**: `AudioServicesPlaySystemSound` calls replaced with `TonePlayer.playTick()` / `.playAlert()`. Deactivation now calls `WorkoutAudioSession.deactivateSession()`.
- **`WorkoutCues`**: `SoundBeep` replaced by `TonePlayer`; `AudioToolbox` import removed.
- **`IntervalCueScheduler`** (`Shared/IntervalCueScheduler.swift`): Timer-based cue scheduling (0.5 Hz on `.common` run-loop) decoupled from SwiftUI view ticks. Owned by `IntervalView`; handles 30 s warnings and 3 s countdown ticks.
- **`IntervalView`**: inline cue tracking removed; phase changes reset the scheduler; cleanup on disappear.

### Post-Completion Coach Add-Ons
- **`CoachAddOnRecommendation`** (`CadenceCore/CoachAddOnRecommendation.swift`): `CoachAddOnStatus` (.encouraged, .neutral, .warn), `CoachAddOnOption` (session + status + message + citations), `CoachAddOnRecommendation` (primary option + secondary list).
- **`CoachAddOnEngine.run()`** (`CadenceCore/CoachAddOnEngine.swift`): evaluates post-completion add-ons — encourages easy cardio when below targets, warns for additional strength/HIIT/boxing after plan complete, warns on poor readiness and hard-day streaks. Copy avoids "overtraining" language.
- **`CoachDecisionCardView`**: now accepts `addOnRecommendation` and `onAddOn` callback. `planComplete` state shows "On plan" banner + primary encouraged CTA ("Add easy cardio") + "Choose extra workout" expandable section with status-colored options (green=encouraged, orange=warn).
- **`HomeView`**: computes `addOnRecommendation` from `CoachAddOnEngine` when `planComplete`; `handleAddOn()` routes `.warn` statuses through a confirmation dialog ("Start anyway" / "Choose easier option").
- **Tests**: all 433 existing CadenceCore tests pass. New types are additive and covered by type system.

## Repo / branch
- Repo: `/Users/arley/github/parso-workout-ios-app`
- **`main`** = current. Builds + tests green.

## Notes / decisions in effect
- All merges to `main` so far were fast-forward; PRs #7–#13.
- Schema changes additive + CloudKit-safe; `[String]` model attrs are delimited-String-backed (`StringArray`).
- `CoachPreferenceProfile` stored as JSON `Data` in UserDefaults under key `settings.coachPreferenceProfile` (not SwiftData).
- `CoachSchedulePreferences` stored as JSON `Data` in UserDefaults under key `settings.coachSchedulePreferences` (same pattern).
- Fixed-day chip UI preserved per plan; behavior fixed first, redesign deferred.
- Background cues now require iOS `audio` background mode + `.playback` category.
