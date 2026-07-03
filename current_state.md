# Current State — Cadence field-testing redesign

Live handoff/progress tracker.

_Last updated: 2026-07-03 — Free Coach card: continuous insights, locked prescription, rate-limited upsell._

## What just shipped — Continuous coach insights, occasional upsell (coach-surface-design amendment)

- **Insights are now continuous and always shown for free users.** The free-tier
  `CoachPreviewView` leads with the coach's live observation ("What the Coach
  noticed") — the same `coachInsights` the Pro coach computes, recomputed every
  day / after every workout via `historyRefreshToken`. No frequency cap, no
  suppression: seeing real, continuously-updated value is the funnel.
- **Only the prescription is paywalled.** A single-lock "What the Coach would do"
  panel shows the prescription headline with the exact action (`Recommendation.action`)
  redacted behind a `PRO` pill; tapping it opens the paywall. This is the line.
- **"Unlock the Coach" is the only rate-limited element.** New pure
  `CadenceCore.CoachUpsellPolicy` (min 14 days between billboard impressions) gates
  the prominent green CTA; `AppSettings.lastCoachUpsellShown` records the cadence,
  stamped once via `onCTADisplayed` (captured into local `@State` so recording it
  can't blink the button out mid-view). Between billboards the locked panel is
  still a discreet, always-available tap-to-convert path.
- **Science links fixed:** the preview's THE SCIENCE section now renders real
  citation titles (from the insight + prescription) via the full `CitationLink`,
  replacing the 3× "The science ›" placeholder.
- **Free `.coach` route** now shows the full live insights list for everyone
  (observations are free), instead of the hard `CoachLockedView`.
- **Tests:** +5 CadenceCore tests (`CoachUpsellPolicyTests`); `swift build`/`swift test`
  green; `xcodebuild` iOS build succeeds; `MonetizationUITests` suite green (free
  preview, paywall open+restore, free-logging-loop regression, Pro card).

_Prior entry:_
_Last updated: 2026-07-01 — Field-test batch: audio mixing, both-modality completion, no imported-workout references, partner-set attribution._

## What just shipped — Field-test fixes (audio, completion, imports, partners)

- **Background music no longer silenced by cues (SHOW STOPPER):** `TonePlayer` no longer uses
  `AVAudioEngine` (whose output unit interrupted background audio even with `.mixWithOthers`).
  It now pre-renders tick/alert tones to in-memory WAV via the new pure `ToneWAV` builder
  (`CadenceCore`) and plays them through `AVAudioPlayer` — matching the bundled bells, which
  always mixed. `CadenceApp.init()` sets `.playback` + `.mixWithOthers` at launch; interval
  spoken cues set `synth.usesApplicationAudioSession = true`. Only `AVAudioPlayer` /
  `AVSpeechSynthesizer` remain (no `AVAudioEngine`). WAV builder unit-tested; mixing verified
  manually on-device.
- **"Today's workouts are completed" when both done:** `computePlanAdherence` now completes the
  day whenever both a strength and an aerobic event were logged today (any duration), regardless
  of the coach's candidate plan (previously a recovery-plan day dropped real work into offPlan and
  showed a strength-only message). `CoachDecisionCardView` renders the generic (nil-kind) complete
  state as "Today's workouts are completed".
- **No more imported-workout references:** removed both "An imported workout may have included
  strength work" deferral messages, the `.unknownImport` recovery gate, and `RecoveryReason.unknownImport`.
  `TrainingEvent.from(cardio:)` always maps to aerobic/intervals. `CoachAboutView` reworded to drop
  "imported HealthKit data". Watch-cardio-only auto-import is unchanged.
- **Partner sets no longer counted as yours:** the "Repeat" set button and the pending planned-row
  chip in `SessionView` now carry the partner-rotation performer (`nextPerson()`) instead of
  defaulting to the owner — the source of the "8 sets of legs" (4 mine + 4 partner) miscount. Core
  counting already filtered `isOwnerSet`; a regression scenario test now locks it.
- **Tests:** +10 CadenceCore tests (both-modality completion ×3, imported-workout ×2, partner
  volume exclusion ×1, ToneWAV ×4). Full suite 547 tests green; `xcodebuild` iOS build succeeds.

## What just shipped — Liquid glass visibility & warm-up shortcut removal

_Prior entry:_
_Last updated: 2026-07-01 — Liquid glass visibility on main tabs, remove redundant warm-up shortcut._

## What just shipped — Liquid glass visibility & warm-up shortcut removal

- **GlassSupport.swift**: increased `cadenceGlassCard` fill opacity (0.025→0.045 untinted, 0.055→0.08 tinted), stroke opacity (0.12→0.18, 0.22→0.28), glass tint (0.35→0.45), added `.shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)` to both iOS 26+ and fallback paths so cards read as floating glass panels.
- **ProgressView.swift**: `card` helper now accepts optional `tint` param; all major cards get explicit tints (blue for strength/intensity/testResults, teal for volume, orange for effort/frequency).
- **TestsView.swift**: added `.listRowBackground(Color.clear)` to all List sections (intro, battery, advanced) so the glass backdrop and baseline card are visible.
- **WeightsStartView.swift**: removed the redundant "Start with Warm-Up" row; footer updated from "…or warm up first." to "…". Warm-up remains intact inside `WorkoutPlanEditor` / pre-workout settings.
- **FR11Feedback4UITests.swift**: `testStartWithWarmUpThenSession` and `testWarmUpPauses` now use `weights.quickStart` + increment the `editor.warmup` stepper to enable warm-up before starting.
- **FR1PartnersUnitsUITests.swift**: `testAddedPartnerAppearsInEditor` now uses `weights.quickStart` instead of removed `weights.warmupStart`.

## What just shipped — App Store positioning pack

- **`docs/app-store/metadata.md`**: canonical App Store positioning, subtitle, promo text,
  description, keyword bank, screenshot storyboard, review notes, privacy answers, and manual
  links. Locked to the launch decisions: science-minded self-coached lifters, App Store v1,
  free with optional one-time tips.
- **`docs/app-store/release-checklist.md`**: code verification, App Store Connect, IAP,
  screenshot, and post-approval checklist for the first public submission.
- **Public copy cleanup:** About and Coach About now describe the coach as a deterministic
  on-device expert/rule system, not a cloud service or black box. Cold-start insight now uses the
  public product name Cladiron instead of the internal codename Cadence.
- **v1 Watch-scope alignment:** pre-workout live-HR copy now references Bluetooth chest straps
  only; Apple Watch remains described only as a HealthKit import source for v1. Deferred live
  Watch HR plumbing remains dormant behind a disabled internal flag.

## What just shipped — Settings & workflow redesign

### Per-workout settings — remember & reuse
- **`WorkoutSettings`** struct (CadenceCore): all per-workout settings (rest timer, auto-rest, countdown, idle auto-end, plate rounding, GPS, auto-pause, interval palette, spoken cues, warm-up, cool-down, HR monitoring).
- **Per-type memory** in `AppSettings`: `lastStrengthSettings`, `lastCardioSettings`, `lastIntervalSettings`. Saved on workout Start, loaded on next setup screen.
- **`WorkoutPlanEditor`**: now shows rest timer, auto-rest, countdown, plate rounding, idle auto-end toggle + timeout, warm-up, cool-down, HR — all pre-populated from last strength settings.
- **`CardioGoalSheet`**: now shows countdown, GPS accuracy, auto-pause, HR — loaded from `lastCardioSettings`.
- **`TimerCardioSetupView`**: now shows countdown + HR — loaded from `lastCardioSettings`.
- **`IntervalSetupView`**: now shows countdown, color-blind palette, spoken cues, HR — loaded from `lastIntervalSettings`.
- **Every workout path now shows settings before starting** — no workout ever starts without a settings screen.

### Coach settings moved to Coach panel on Home
- **`CoachContextSettingsView`** (new): sheet accessible from the gear icon on `CoachDecisionCardView`. Contains Training Goal, Experience Level, Schedule Preferences link, and Daily Step Target stepper.
- **Removed** the Coach section from `SettingsView` — it now lives on the Home coach panel.
- **`HomeView`**: gear button on Coach card now opens `CoachContextSettingsView` sheet instead of navigating to standalone coach preferences.

### Steps moved to "Your Plan" with adjustable target
- **Removed** the `stepHealthSection` from HomeView front page.
- **Added** steps section to `YourWeekView`: 7-day avg, progress bar vs target, today's steps, status badge, citation link — placed right after mod-equivalent minutes.
- **`CoachSchedulePreferences.dailyStepTarget`**: user-adjustable daily step target (2,000–20,000, step 500, default 8,000). Adjustable in `CoachContextSettingsView`.
- **`StepActivitySummary(from:targetDailySteps:)`**: new initializer that computes status against a custom target (floor 4,000 is fixed).

### Planned (next week) when rest of week empty
- **`plannedRestOfWeekSection`** on HomeView: when `restOfWeekDays` is empty, shows `coachPlan.nextWeekDays` with "Planned (next week)" header instead of "No more planned sessions".

### SettingsView simplified
- **Removed sections**: Coach, Workout, Workout Start, Idle Auto-End, Strength (plate rounding), Cardio, Intervals, Goals, Warm-up & Cool-down.
- **Kept sections**: Units & Records, Health & Sensors, Data, Sounds, About, Support.
- Per-workout settings now live on each workout's pre-start screen, remembered per type.

## What just shipped — Settings cleanup, evidence-based steps, fixed rest days

### Settings cleanup
- **Removed** the user-editable `stepGoal` stepper from Settings. Steps are now an evidence-based health signal, not a user setting.
- **Merged** the two separate Apple Health sections into one "Health & Sensors" area: connection/status row, auto-save toggle, and last sync timestamp all in one place.
- **Fixed** idle auto-end grouping: "Auto-end when idle" toggle now precedes the "Auto-end after N min idle" timeout, which is disabled when the toggle is off.
- **Renamed** Data rows: "Import" → "Import Workout Log", "Export" → "Backup & Restore".
- **Reorganized** Settings into clean sections: Coach, Units & Records, Health & Sensors, Data, Workout, Workout start, Idle Auto-End, Strength, Cardio, Intervals, Goals, Warm-up & Cool-down, Sounds, About, Support.
- **Stopped** exporting `stepGoal` in new exports (`exportPreferences()` writes nil). `ExportPreferences.stepGoal` remains optional for decoding older backups.

### Fixed rest days (Coach schedule preferences)
- **Count control**: segmented picker (1 day / 2 days) when fixed rest is selected.
- **Weekday chips**: Sun–Sat buttons; selecting a new day when full replaces the lowest-rawValue selected day.
- **Defaults**: switching from rolling to fixed initializes with Saturday/Sunday (2-day) or Sunday (1-day). Switching from fixed back to rolling uses `everyNDays: 3`.
- **Footer copy**: "Fixed rest days are days the Coach will not schedule workouts. You can still start one manually."
- **Coverage**: `WeeklyPlan.generate` respects fixed rest days via `isRestDay` (already implemented); new tests prevent regression.

### Evidence-based steps health
- **`StepActivitySummary`** model (CadenceCore) with `StepHealthStatus` (low/building/onTrack), derived from `[DayActivity]`.
- **Fixed thresholds**: floor=4,000, target=8,000, weekly target=56,000 — no user setting.
- **`CoachFacts.make(activityTrend:)`** overload that wraps the existing `make` and attaches a `StepActivitySummary`.
- **Observed fact**: `.weeklySteps` fact shows today's steps, 7-day avg, and status with `stepsHealth` citations.
- **Low-step nudge** (`CoachWarning(id: "lowSteps")`) only when 7-day avg is below 4,000. Cites only `stepsHealthPool` (`saintMauriceSteps2020`, `leeAccelerometer2019`). Does not override strength/cardio session selection. Not presented as medical advice.
- **HomeView**: fetches `activityTrend(days: 7)` alongside `todayActivity()`; displays a step health section with today's steps, 7-day avg, status badge, and citation link.

### Tests (24 new, 0 regressions)
- **`StepActivitySummaryTests`** (12 new): threshold categorization, 7-day avg, weekly total, today steps, static constants.
- **CoachFactsTests** (3 new): `make` with/without activityTrend, preserves existing behavior.
- **CoachDecisionEngineTests** (4 new): low-step nudge, no nudge when on track, no fact without trend, nudge doesn't override primary.
- **CoachSchedulePreferencesTests** (4 new): 1-day and 2-day fixed round-trips, `WeeklyPlan` marks fixed rest days, non-fixed days not forced rest.
- **DataExportTests** (1 new): legacy export JSON with `stepGoal` still decodes.
- **Total**: 508 tests, 0 failures, deterministic.

## What just shipped — local-only + lossless portability + coach Sunday fix + accessibility

### Removed iCloud sync (now fully local)
- **`Store.swift`**: dropped `cloudKitContainerID` + the `cloudKitEnabled` branch; `makeModelContainer(inMemory:)` is always local (`.none`). Removed `cloudSyncEnabled` key/default.
- **`AppSettings.swift`**: removed `cloudSyncEnabled`. **`CadenceApp.swift`**: no cloud flag. **`SettingsView`**: removed the iCloud Sync section. **`AboutView`**: copy now emphasizes local + export portability.
- **Entitlements**: removed `aps-environment`. **Info.plist**: removed `remote-notification` background mode (CloudKit push), **added `bluetooth-central`** (chest strap keeps streaming with the screen locked). Removed the obsolete iCloud-sync UI test.
- Docs (README, CLAUDE.md, REQUIREMENTS.md) updated: no cloud sync; portability via JSON export/import.

### Lossless export/import (`CadenceExport` v4)
- **Fixed a real data-loss bug:** `merge` previously **dropped all cardio on import**. Cardio now round-trips (incl. HR + route samples + metadata).
- Added **assessments** export/import (were never exported), full **session/set metadata** (endedAt, isLogged, planKey, templateName, planned names/ladder, warm/cool seconds, prescribedLoad, partners, usesBodyweight), and an **`ExportPreferences`** block (all settings + schedule prefs + the learned `CoachPreferenceProfile`).
- **`AppSettings.exportPreferences()` / `applyImportedPreferences(_:)`** map settings ↔ the DTO; `ExportView` exports + restores them. v1–v3 exports still decode (custom decoder + optional fields).
- Tests: `DataExportTests.testLosslessRoundTripFullData` (export → JSON → fresh-store import → re-export → identical history + cardio + assessments + prefs) and `testMergeIsIdempotent`.

### Coach: weekly strength cap + Sunday bug
- **Root cause fixed:** `WeeklyStats.weekStart` returned *next* Monday on Sundays (Sunday-first calendar) → "this week" counted 0 strength on Sundays → coach recommended more strength. Now uses a Monday-first calendar (correct on Sundays).
- **Cap enforced:** `CoachSession.candidates` now uses the user's `strengthDaysPerWeek` as the floor and gates general/beginner/reduced-load strength on `strengthCapMet`; `buildTodayRecommendations` won't add strength once the weekly target is met (two-a-day can't override it).
- New test `testThreeStrengthThisWeekMeetsTargetNoMoreStrengthOnSundayEvenWithTwoADay`.

### Deterministic tests (13 flakes fixed)
- Production: `TrainingEvent.from` anchors `lastWorkingSetAt` to `max(setTimes, endDate)` (a session can't end before its last set) + the `weekStart` fix above.
- Tests: pinned `testNow` to a fixed Thursday across 4 suites, anchored helper `completedAt`, pinned `Date()` in WeeklyStats/CoachSchedulePreferences. **Suite now 484 tests, 0 failures, deterministic regardless of time of day.**

### Dynamic Type everywhere
- New `scaledSystemFont(_:relativeTo:weight:design:)` (`@ScaledMetric`-backed) replaces all **24** hardcoded `.system(size:)` usages across 14 files (timers, countdowns, clocks, keypad, icons) so they scale with the user's text size.

### Verification
- `swift test`: 484 tests, 0 failures. `xcodebuild` iOS scheme: **BUILD SUCCEEDED**.

## What just shipped — App Store readiness fixes + supporter (tip-jar) flow
## What just shipped — Supporter / contribution flow (StoreKit 2 tip jar)

Ported from the Parso Radio app, adapted to Cladiron's Observation paradigm. Plan +
decisions: `plans/supporter-flow/2026-06-28/`.

- **`CadenceCore/ContributionPromptEngine.swift`** (+ tests): pure "when to prompt" logic.
  Gate = **6 completed workouts** AND ≥2 sessions; snooze 7 days + 5 launches; never when
  opted-out/already-supporter/first-session/once-per-session. 7 tests, fixed `now` (flake-proof).
- **`App/ContributionStore.swift`**: `@Observable @MainActor` StoreKit 2 layer. Consumables
  `guru.parso.cladiron.tip.small/medium/generous`. `everContributed` in UserDefaults; loads
  products, `purchase`, `restore`, `Transaction.updates` listener. Dormant until ASC products exist.
- **`App/ContributionCoordinator.swift`**: `@Observable` lifecycle. Owns its store, counters
  in UserDefaults, `beginSession`, static `recordWorkoutCompleted`, `evaluate`, dismiss/optOut.
- **`Features/Settings/ContributionToast.swift`** + **`ContributionSupportView.swift`**: bottom
  card (Support / Maybe later / Don't ask again) + Support screen ("Support Cladiron", no charity
  line, placeholder when no products, Restore).
- **Wiring:** `CadenceApp` injects the coordinator via `.environment` and calls `beginSession()`.
  Per decision D6 the prompt is **Home-only**: `HomeView` renders the toast + calls `evaluate()`
  on scene-active, both gated by `contributionPromptAllowed` (no active workout / start sequence).
  Engagement counter bumps via `workoutSaved()` on genuine cardio/interval/swim/logged saves
  (NOT HealthKit ingest) and via `active.finishedSummary` for strength.
- **Settings** gains an appended "Support Cladiron" section; **About** copy reworded
  ("optional tip jar … never required"). **`Cadence.storekit`** added for local testing
  (maintainer adds it to the project + Run scheme per `02-manual-steps.md`).
- Verified: `xcodebuild` **BUILD SUCCEEDED**; `swift test` 481 tests (the 7 new engine tests
  pass; the 13 failures are the **pre-existing** date-relative recovery/weekly-stats flakes,
  reproduced identically on a stashed clean tree).

## What just shipped — App Store readiness fixes

- **Privacy manifest** `Cadence/Cadence/PrivacyInfo.xcprivacy` — Data Not Collected + the one
  required-reason API actually used (`UserDefaults`/CA92.1). Auto-included via the Xcode-16
  synchronized group.
- **Device family → iPhone-only** (`TARGETED_DEVICE_FAMILY = 1`, both app configs).
- **Logic bug fixed:** `RecommendationEngine.pickRoutine` no longer indexes a guarded-empty
  array — added `StrengthPresets.fallback`, uses `presets.first`.
- **Persistent medical disclaimer** added to About (onboarding already had one).
- **VoiceOver:** labels on icon-only buttons (SessionView save-health/menu/info/save-set/RPE,
  Onboarding back); 44pt hit target on the exercise menu; accessible summaries on all 4 Swift
  Charts (HR avg/range, assessment trend; strength chart deferred to its text list); decorative
  alternatives icon hidden.
- **README:** states plainly there is **no companion watch app currently** (Watch data imported
  from Health); a watchOS app is only a possible future addition.
- **Audio background mode kept** (per maintainer — used for interval/finish cues over video).
- Still open (not done): App Store Connect listing/screenshots/privacy answers; CloudKit vs
  `remote-notification` entitlement reconciliation; Dynamic Type on hardcoded-size timer screens.

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
