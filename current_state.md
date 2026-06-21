# Current State — Cadence field-testing redesign

Live handoff/progress tracker.

_Last updated: 2026-06-21 — Home redesign + onboarding implemented on branch
`feat/home-redesign-onboarding` (off `main`): Coach card gains its own green Start
button; 5 full-width pill buttons collapsed into a compact quick-actions row; the
4 stat tiles replaced by a calm "This week" card; dead `bodyPartsPresented` sheet
and `BodyPartQuickStartView` trigger removed. Plus a 4-screen onboarding flow
(privacy → goal → experience → units+Health) that captures what the Coach engine
needs in ~20 s. No engine/data-model changes.

## Repo / branch
- Repo: `/Users/arley/github/parso-workout-ios-app` (this is the user's working copy).
- **`main`** = All phases + round 2/3/4 + feedback batches + home-strength-first + home-redesign-onboarding, all merged. The app on `main` builds + runs clean.
- **CadenceCore: 243/243 green; iOS build: green** (verified 2026-06-21).
- **Next branch:** none currently active (just shipped `feat/home-redesign-onboarding`).

## What shipped on `feat/home-redesign-onboarding` (this branch → main)
- **Home redesign:** Coach card gains green "Start workout" button (folded from standalone pill).
  5 full-width pills collapsed into a compact `quickActionsRow` (Strength/Cardio/Log/Programs).
  Stat tiles replaced by a calm `thisWeekCard` with 4 metrics + missing body parts.
  Dead `bodyPartsPresented` @State + `.sheet` removed.
- **Onboarding:** 4-screen flow (Welcome/Privacy → Goal → Experience → Units+Health) presented
  via `fullScreenCover` in `RootTabView`. `AppSettings.hasCompletedOnboarding` persists
  completion. `-showOnboarding` launch arg overrides `-uiTest` skip.
- **Tests:** 10 new `OnboardingUITests`, 6 new home-redesign tests in `P3CoachHomeUITests`,
  2 removed tile-tap tests in `FR15Batch8UITests` replaced with `thisWeekCard` test.
- **CadenceCore: 243/243 green; iOS build + test-build: green.**
- No engine/data-model changes.

## How to work here (methodology — also in CLAUDE.md)
- Plan to disk first for big asks (`plans/field-testing/<date>/`); implement
  phase-by-phase, one PR each; update THIS file at each phase start.
- Logic in `CadenceCore` (`swift test` — reliable). UI via `xcodebuild` (flaky on a
  degraded sim).
- **Degraded-sim gotcha:** if `xcodebuild test` launches balloon to ~45s with
  `no debugger version`, restart CoreSimulator:
  `xcrun simctl shutdown all; killall -9 com.apple.CoreSimulator.CoreSimulatorService`
  then boot the device again. Run non-parallel for reliable signal.

## Commands
- Core tests: `cd CadenceCore && swift test`
- Build: `xcodebuild -project Cadence/Cadence.xcodeproj -scheme Cadence -destination 'id=FC7B2F90-A27B-4BD5-9313-7B267636E165' build`
- UI suite (non-parallel): same with `-parallel-testing-enabled NO test`
  (sim id `FC7B2F90-A27B-4BD5-9313-7B267636E165` = iPhone 16; pick any booted one).
- Inspect a failure: `xcrun xcresulttool get test-results test-details --test-id 'SuiteName/testName()' --path <latest .xcresult>`

## Notes / decisions in effect
- All merges to `main` so far were fast-forward; PRs #7–#13.
- Schema changes additive + CloudKit-safe; `[String]` model attrs are delimited-
  String-backed (`StringArray`) — do NOT reintroduce raw `[String]` `@Model` attrs.
- `opening-closing-bell.mp3` / `warning-bell.mp3` also sit in the repo root (source
  copies); the bundled copies are under `Cadence/Cadence/Sounds/`.
