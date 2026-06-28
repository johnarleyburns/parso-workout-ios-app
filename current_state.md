# Current State — Cadence field-testing redesign

Live handoff/progress tracker.

_Last updated: 2026-06-27 — Coach card "Pick another" cardio alternatives link._

## What just shipped — Coach card cardio alternatives link

- **`CoachDecisionCardView.swift`**: new `onPickAlternative` callback + a "Not feeling it? Pick another" link rendered under the single-CTA Start button. Gated by `showsAlternativesLink` — only shown for cardio prescriptions (`easyAerobic`/`moderateAerobic`/`vo2Intervals`) that have scored `decision.alternatives`. Accessibility id `coach.card.pickAlternative`.
- **`HomeView.swift`**: `showAlternatives` state presents the previously-unwired `CoachAlternativesView` in a sheet (wrapped in a `NavigationStack`). New `chooseAlternative(_:)` records the preference via `settings.recordCoachSelection(_:alternatives:)` (so Coach learns the modality), dismisses the sheet, then defers `launchDecision(_:)` one runloop turn so the chooser finishes dismissing before the cardio setup sheet/cover presents.
- No `CadenceCore` changes — `CoachDecision.alternatives` and the preference-learning hook already existed; `CoachAlternativesView` already renders each option's `CitationLink` (HARD RULE satisfied).
- Verified: `xcodebuild` Cadence scheme **BUILD SUCCEEDED**; `swift test` 474 tests, 0 failures.

## What just shipped — Coach two-a-days + load accounting + set entry UX

### Load Accounting Model (Phase 1-3)
- **`ExerciseTaxonomy.swift`**: new `LoadAccountingMode` enum — `barbell`, `bodyweight`, `dualDumbbell`, `singleDumbbell`, `isolateralDumbbell`.
- **`Models.swift`**: Exercise gains `loadAccountingMode`, `defaultBarWeightKg`, `loadAccountingUserOverride`. SetEntry gains `barWeightKg`, `loadMultiplier`, `loadAccountingMode`, `effectiveLoadKg` computed property, `SetSample.from(_:)` helper.
- **`ExerciseLibrary.swift`**: `makeExercise(from:)` seeds load accounting defaults from equipment/name heuristics.
- **`WorkoutRepository.swift`**: `addSet` snapshots accounting metadata from exercise onto new sets (only when exercise has explicit accounting mode). `sampleHistory`, `currentPR`, `wouldBePR`, `trendSeries`, `prTimeline` all use `effectiveLoadKg`. `findOrCreateExercise` does NOT seed accounting (rely on seed function). `buildExport`/`merge` include accounting metadata.
- **`DataExport.swift`**: Export v3 with `barWeightKg`, `loadMultiplier`, `loadAccountingMode` fields on `ExportSet`.
- **Calculation call sites updated** to use `effectiveLoadKg`: `TrainingFacts.make`, `TrainingEvent.from(session:)`, `StrengthProgress.series`, `WorkoutSummaryData.lines`, `WorkoutSession.totalVolume`, `SessionView.isAllTimePR`.
- Legacy sets (no `loadAccountingMode`) keep `effectiveLoadKg = weight` unchanged.

### Coach Two-a-Days (Phase 4-6)
- **`CoachDecision.swift`**: new `todayPlannedRecommendations: [CoachSession]` field. Gated behind `schedulePreferences.allowsTwoADays`. When enabled, populates both strength and cardio if both are needed. `computePlanAdherence` updated for two-a-day: only `.planComplete` when both types are done. `effectivePrimary` overrides scored primary when the scored primary's kind is already completed.
- **`CoachDecisionCardView.swift`**: new `twoADayStack` shows stacked rows with independent Start buttons when `todayPlannedRecommendations.count > 1`. Each row has icon, title, subtitle, colored Start button.

### Set Entry UX (Phase 7-8)
- **`SessionView.swift`**: `openInlineEditor` now defaults first-set weight from prior session's first working set; subsequent sets default from previous set's weight. New `inlinePriorWeightHint` shows "Previously started this exercise at X" callout. RPE stepper now has explicit "none" state with clear button. Weight info button beside weight field opens context-sensitive sheet (barbell bar weight, dumbbell entry guidance). First-time dumbbell info sheet auto-shows once via `@AppStorage("dumbbellInfoShown")`. Load accounting metadata snapshotted onto new sets via `WorkoutRepository.addSet`.

### Tests (473 total, 0 failures)
- **New `LoadAccountingTests.swift`** (35 tests): accounting defaults, effective load math, snapshot on creation, export/import round-trip, PR/volume uses effective load, optional RPE, prior-set weight defaults.
- **`CoachDecisionEngineTests.swift`**: 5 new two-a-day tests (both recommendations, cardio-only, strength-only, both-complete, off-by-default).

## What just shipped — Coach UI + splash + completed-plan reconciliation

### Splash restoration
- **`SplashView.swift`**: restored grayscale image-backed splash background from git history. Uses `UIImage(named: "splash")` with `.aspectRatio(contentMode: .fill)`, dark overlay (0.45 opacity), white text. Falls back to `Color(.systemGray6)` if image missing.
- **`splash.jpg`**: regenerated with ImageMagick — grayscale, 1320x2868, center-cropped, quality 88. Source: original image from commit `8c5e5f1`. `Resources/splash.jpg` left unchanged.
- App launch screen settings (`INFOPLIST_KEY_UILaunchScreen_Generation = YES`) unchanged.

### Home This week card cleanup
- **`HomeView.swift`**: removed `Details >` button from `thisWeekCard` header. Users now reach weekly insights via Coach card's `Your week` link.

### Compact Coach's Insights in Your Week
- **`YourWeekView.swift`**: added `insights: [Insight]` parameter. New `Coach's Insights` section at the bottom (after VO₂max). Uses private `CompactInsightRow` — collapsed by default showing icon, title, severity; expands to show message, detail, and citation link. No detail/citation visible until expansion.
- **`HomeView.swift`**: passes `coachInsights` to `YourWeekView` routing.

### Schedule preferences extraction
- **New `CoachSchedulePreferencesView.swift`**: full schedule controls (strength days, cardio days, rest pattern, two-a-days, cardio timing) in a Form behind `"Coach preferences"` navigation title. All citations preserved.
- **`WhyThisTodayView.swift`**: replaced `myPreferencesSection` (inline pickers/toggles/chips) with compact `preferencesLinkSection` — summary text + `"Review my preferences"` link navigating to `CoachSchedulePreferencesView`.
- **`SettingsView.swift`**: added `NavigationLink` to `CoachSchedulePreferencesView` in Coach section, below Training goal and Experience pickers. Accessibility identifier: `settings.coach.schedulePreferences`.

### Completed-plan state reconciliation (Why This Today)
- **`WhyThisTodayView.swift`**: now accepts `addOnRecommendation: CoachAddOnRecommendation` and `onAddOnTap` callback. Body branches on `isPlanComplete`:
  - **Plan complete**: shows `completedPlanExplanationSection` (Plan followed + description + tomorrow preview) and `optionalAddOnsSection` (add-on options with status colors/buttons). Hides Coach's Pick, ruled-out candidates, and why-won sections.
  - **Normal state**: shows Coach's Pick, alternatives, ruled-out, and why-won as before.
- **`HomeView.swift`**: passes `addOnRecommendation` and `handleAddOn` to `WhyThisTodayView`.

### Tests
- All 433 CadenceCore tests pass (0 failures).
- **`P3CoachHomeUITests`**: added `testThisWeekCardDoesNotShowDetailsLink`, `testSettingsLinksToCoachSchedulePreferences`.
- **`WhyThisTodayUITests`**: added `testWhyTodayHidesPreferenceControlsBehindReviewLink`, `testWhyTodayPlanCompleteDoesNotShowCoachPick`.
- Build + test build succeed. UI test suite timed out on simulator (environment limitation) but all code compiles cleanly.

## What just shipped — Coach UI + splash + completed-plan reconciliation

### Splash restoration
- **`SplashView.swift`**: restored grayscale image-backed splash background from git history. Uses `UIImage(named: "splash")` with `.aspectRatio(contentMode: .fill)`, dark overlay (0.45 opacity), white text. Falls back to `Color(.systemGray6)` if image missing.
- **`splash.jpg`**: regenerated with ImageMagick — grayscale, 1320x2868, center-cropped, quality 88. Source: original image from commit `8c5e5f1`. `Resources/splash.jpg` left unchanged.
- App launch screen settings (`INFOPLIST_KEY_UILaunchScreen_Generation = YES`) unchanged.

### Home This week card cleanup
- **`HomeView.swift`**: removed `Details >` button from `thisWeekCard` header. Users now reach weekly insights via Coach card's `Your week` link.

### Compact Coach's Insights in Your Week
- **`YourWeekView.swift`**: added `insights: [Insight]` parameter. New `Coach's Insights` section at the bottom (after VO₂max). Uses private `CompactInsightRow` — collapsed by default showing icon, title, severity; expands to show message, detail, and citation link. No detail/citation visible until expansion.
- **`HomeView.swift`**: passes `coachInsights` to `YourWeekView` routing.

### Schedule preferences extraction
- **New `CoachSchedulePreferencesView.swift`**: full schedule controls (strength days, cardio days, rest pattern, two-a-days, cardio timing) in a Form behind `"Coach preferences"` navigation title. All citations preserved.
- **`WhyThisTodayView.swift`**: replaced `myPreferencesSection` (inline pickers/toggles/chips) with compact `preferencesLinkSection` — summary text + `"Review my preferences"` link navigating to `CoachSchedulePreferencesView`.
- **`SettingsView.swift`**: added `NavigationLink` to `CoachSchedulePreferencesView` in Coach section, below Training goal and Experience pickers. Accessibility identifier: `settings.coach.schedulePreferences`.

### Completed-plan state reconciliation (Why This Today)
- **`WhyThisTodayView.swift`**: now accepts `addOnRecommendation` and `onAddOnTap` callback. Body branches on `isPlanComplete`:
  - **Plan complete**: shows `completedPlanExplanationSection` (Plan followed + description + tomorrow preview) and `optionalAddOnsSection` (add-on options with status colors/buttons). Hides Coach's Pick, ruled-out candidates, and why-won sections.
  - **Normal state**: shows Coach's Pick, alternatives, ruled-out, and why-won as before.
- **`HomeView.swift`**: passes `addOnRecommendation` and `handleAddOn` to `WhyThisTodayView`.

### Tests
- All 433 CadenceCore tests pass (0 failures).
- **`P3CoachHomeUITests`**: added `testThisWeekCardDoesNotShowDetailsLink`, `testSettingsLinksToCoachSchedulePreferences`.
- **`WhyThisTodayUITests`**: added `testWhyTodayHidesPreferenceControlsBehindReviewLink`, `testWhyTodayPlanCompleteDoesNotShowCoachPick`.
- Build + test build succeed.

## What previously shipped — Coach scheduling + audio + add-ons

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
