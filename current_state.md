# Current State — Cadence field-testing redesign

Live handoff/progress tracker.

_Last updated: 2026-06-23 — Coach Why This Today + Preferences implemented directly on
`main` (single-phase feature from `plans/field-testing/2026-06-23/`)._

## Repo / branch
- Repo: `/Users/arley/github/parso-workout-ios-app`
- **`main`** = All prior phases + coach-why-today-preferences, merged. Builds + runs clean.
- **CadenceCore: 337/337 green; iOS build: green; WhyThisTodayUITests: 4/4 green** (verified 2026-06-23).

## What just shipped — Coach Why This Today + Preferences
- **`ObservedFact` replaced** with rich model (`Kind`, `title`, `value`, `detail`, `occurredAt`). Last Cardio added. Summary facts use static values, never `Text(date, style: .relative)`.
- **Duplicate Evidence section removed.** Citations are inline-only; no generic Evidence header when claims carry their own science links.
- **COACH'S PICK section** added directly below What you did, showing the actual prescription (title, duration, modality, intensity, target grid).
- **Alternatives flow:** `alternatives >` opens `CoachAlternativesView` with eligible full-match / closest-match options. Selecting an alternative launches it and records a `CoachPreferenceEvent`.
- **`CoachPreferenceProfile`** (new file in CadenceCore) — Codable profile stored in UserDefaults via `AppSettings.coachPreferenceProfile`. `CoachDecisionEngine.run` now accepts profile and adjusts scoring after eligibility gates. Preferences reorder eligible candidates but never override pain, active-workout, recovery, or lower-body-collision gates.
- **Expanded aerobic candidates:** Easy swim/row, moderate cycle/swim/row/boxing now available alongside walk/run.
- **Export v2:** `CadenceExport` version 2 includes optional `coachPreferences: ExportCoachPreferences?`. Old v1 exports still decode (preferences nil). `ExportView` passes `settings.coachPreferenceProfile.exportDTO`. Footer copy updated.
- **UI test seeds:** `coachWhyMixedHistory`, `coachAerobicGap`, `coachCyclePreference`, `coachLowerBodyRecovery`.
- **Tests:** 15 new core unit tests (CoachDecisionEngine + CoachPreferenceProfile + DataExport). 4 new `WhyThisTodayUITests`. Fixed 2 pre-existing build errors in `UITestHelpers.swift` (duplicate `keypadEnter`, `XCUIKeyboardKeyDelete`).
- **New files:** `CoachPreferenceProfile.swift` (core), `CoachAlternativesView.swift` (app), `CoachPreferenceProfileTests.swift` (tests), `WhyThisTodayUITests.swift` (tests).
- **No LLM, no telemetry, no accounts, no server.** Purely deterministic, local, cited.

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
- `CoachPreferenceProfile` stored as JSON `Data` in UserDefaults under key
  `settings.coachPreferenceProfile` (not SwiftData). Cleared in `-uiTest` mode.
