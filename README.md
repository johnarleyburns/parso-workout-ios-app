# Cladiron

An open-source, privacy-first, science-based **strength app** for iPhone and Apple Watch. The complete app—including logging, history, Progress, Tests, Coach, planning, and export—is free forever. An optional one-time $9.99 Supporter contribution unlocks nothing and only adds a Supporter badge. Log strength workouts with per-set tracking and partner rotation from your wrist, get cited coaching recommendations grounded in published research, track PRs, and review your training history. Cardio recording and HIIT intervals are supported on both phone and watch. **Companion Apple Watch app included** — run a full "watch-only fitness" session without your phone: strength (with partners, lbs, warm-up/cool-down), HIIT/Boxing with customizable rounds, and cardio (Run/Walk/Cycle indoor & outdoor, Swim with lap counter, Rowing, Other). Live HR streams from the wrist; every completed workout saves to HealthKit for rings credit and auto-ingests back to the phone. Your data stays on-device, with a full JSON export/import so you can back it up or move it to a fresh install at any time. Cardio activities can also be exchanged as standard FIT files, including heart-rate and GPS route samples; FIT is not a replacement for the lossless JSON backup.

**Every single coaching output cites published, user-navigable science.** Cladiron never makes a recommendation, insight, warning, or deferred decision without a tappable "The science >" link to the study behind it.

**The coach suggests; it does not proscribe.** Your stated weekly targets always win over the coach's auto-recovery instincts — a rest recommendation is advice attached to your plan, never a silent replacement of it. Every coach surface leaves an escape hatch: pick an alternative, choose any cardio, or build a strength session anyway.

## What it does

- **Recovery-aware coaching engine** — a deterministic, on-device rule engine (not AI) that reads strength, cardio, imported HealthKit workouts, passive HealthKit signals (HRV, resting HR, sleep — fused with, never overriding, your self-report), and optional readiness check-ins. It gates every session through hard eligibility checks (same-lift recovery, pattern/body-part windows, high-fatigue deferral, lower-body collision) before scoring candidates against your balanced weekly plan — incorporating preferences learned from alternatives you've chosen. Then explains exactly what was ruled out, why, and which study backs it.
- **Observations + personalized workouts** — Home keeps cited Observations separate from an on-demand, editable Personalized Workout chooser reached from Start Workout. It calculates Minimum (4), Medium (8), and Maximal (12) weekly-set targets from direct/indirect muscle work, shows remaining gaps and safety-cap trims, and never replaces the user's decision to train. Custom and personalized workouts can be scheduled as one-off local date/time snapshots; the retired weekly Plan tab is not part of the primary flow.
- **Watch swimming** — choose Lap Pool (25 m or 50 m, remembered) or Open Water w/GPS. Water lock starts when the workout is running; hold the Crown to unlock. Pool lengths and meters update from Apple's swimming measurements, remain visible on the workout screen, and sync to the phone. Swim help explains wrist-raise settings and security-lock limits; a watchOS passcode lock cannot be bypassed by the app.
- **Today recommendations** — a stable card at about half the screen shows a truncated preview with full WHY and editable setup. Automatic initial and in-workout suggestions exclude exercises from only the last strength workout, with no date cutoff; exercises from earlier workouts remain eligible. Recovery drafts honor exercise exclusions, including Air Squat; WHY and This Week share vigorous-adjusted cardio credit. Chosen weekly training-day targets take precedence over generic hard-streak recovery scoring. Muscle coverage is light green for any work below four sets, half opacity for four to under eight, and solid at eight or more. Easy options offers reviewed light resistance and short walks/cycles. Fill the Gaps puts fresh suggestions and their Start button first; reusable workouts show dates and exercise lists.
- **"Why This Today" screen** — every decision is transparent: what you did, Coach's Pick (with alternatives), what was ruled out (with next eligible time), why the winner was chosen, and tappable science citations for every claim. Selecting an alternative teaches Coach your preferences; your learned profile is included in every JSON export.
- **Coach Research Updates + bibliography** — a versioned changelog of the coaching engine, followed by a full bibliography of every study the coach cites, ordered by author. Each entry explains in one line why the coach uses it and links straight to the paper.
- **Strength logging** — per-set weight/reps with inline last-time recall, quarter-unit load display, visible RPE/RIR entry, auto PR detection, rest timer, and partner rotation with each lifter's sets kept separate.
- **Prescriptive recommendations** — the coach prescribes concrete next-session targets (double progression, deload, volume adjustment) based on your training goal (strength / hypertrophy / endurance), experience level, and recovery state.
- **Assessments** — strength (e1RM, rep-max, push-up, pull-up, plank, hollow hold) and cardio (VO2max field test, Wingate) battery with longitudinal tracking and retest cadence.
- **Progress dashboard** — science-backed adaptation dashboard: e1RM trends, a PR timeline, a training-consistency heatmap, weekly volume vs landmarks, load intensity vs goal, effort/frequency, test results — every interpretation cites its source with tappable "The science >" links.
- **Weekly dashboard** — Home's This Week card tracks strength days, cardio as moderate-equivalent minutes (with the vigorous-counts-double weighting broken out and cited, so 80 hard minutes reading as 158 is explained rather than mysterious), total tonnage, and graded muscle-group/muscle weekly sets: below 4, building to 8, productive through 12, and explicitly above the 12-set maximum. Strength, Cardio, and Volume details are independently expandable, with a compact local anatomy map shown first.
- **Exercise library and training engine** — 873 exercises from the pinned open `free-exercise-db-plusplus` package, with source imagery, evidence-audited muscle roles, a 20-muscle ontology, movement classifications, and deterministic planning primitives.
- **Workout routines** — Full Body A/B, PHUL (4-day), Arnold Split, StrongLifts 5x5, Push/Pull/Legs, Upper/Lower, Calisthenics, Olympic Lifting, plus user-created templates. Every preset cites the relevant evidence.
- **Cardio recording** — GPS outdoor (run/walk/cycle), indoor recording, swim laps, with live HR from a BLE chest strap (Apple Watch workouts are imported from Health afterward).
- **HIIT intervals** — 7 science-backed protocols (Tabata, Norwegian 4x4, Gibala, SIT, REHIT, 10-20-30, Boxing) with work/rest timing, round bells, and warm-up/cool-down.
- **Companion Apple Watch app** — a compact launcher mirrors the phone's workout options and opens the chosen one only on Start. The Lift preview lets you choose partners and rep defaults before starting. Warm-up and cool-down both offer Pause plus +1/+5 minute extenders; cool-down's finish action is End and stops immediately. Set entry repeats the exact last working load and reps when no explicit plan overrides them. Phone-free training from the wrist: strength with precise decimal weights, one-row plate shortcuts, custom exercise creation, partner rotation, and three-bell rest completion; HIIT/Boxing bells mix over music without pausing it; plus a full cardio suite (Run/Walk/Cycle indoor & outdoor, Swim with lap counter, Rowing, Other). Live wrist HR, Health save with rings credit, and automatic sync back to the phone. Watch-logged sets send the entered load and the phone applies each exercise's accounting once, so dumbbell and kettlebell totals are never doubled or halved.
- **BLE chest strap** — CoreBluetooth `0x180D` with exponential-backoff reconnection, battery monitoring, and cold-launch auto-reconnect.
- **Lock-screen workout status** — active iPhone strength workouts publish an ActivityKit status with elapsed time and pause state; Apple Watch workouts use the native HealthKit workout surface.
- **HealthKit** — reads steps, ingests Watch-recorded workouts + HR, and reads HRV, resting heart rate, sleep, and body weight (on-device only) as a passive-readiness prior the coach fuses with your self-report; writes strength/cardio/interval summaries, HR samples, and GPS routes back to Health.
- **Workout home** — the Today list starts Lift, every cardio type, Other, then the coach's Recommend option last. Workout History opens from the upper-left history icon, with Archive and Share actions. Workout Plan opens read-only with each exercise's last-session reps and loads seeded from that exercise's own history (blank only when it has never been trained); Add Exercise sits directly above Start Workout, and adding one never flips the plan into an edit mode.
- **History & trends** — unified strength + cardio history, per-exercise trend charts, workout summary with full per-set detail.
- **Privacy-first, on-device** — SwiftData with no accounts, no third-party server, no ads, and no iCloud mirror in the App Store submission build. Your full training log stays on your iPhone; the Apple Watch relays completed work over WatchConnectivity. A complete, compressed JSON export (`.json.gz`, imports also accept plain `.json`) backs up and moves your data (full history + preferences) to a fresh install. CSV remains a spreadsheet-friendly strength export; FIT is a cardio/activity interchange format and imports back into cardio history.

## Architecture

- `CadenceCore` — Swift package: data model (SwiftData), coaching engine (CoachDecision engine, eligibility gates, weekly planner, insights + recommendations + citations), exercise library, assessment math, PR logic, interval protocols. Both app targets depend on it; headlessly testable with `swift test`.
- `Cadence` — iOS app (primary surface for v1).
- `Cadence Watch App` — a full watchOS companion for phone-free training: strength (with partners), customizable interval workouts, and a complete cardio suite (Run/Walk/Cycle/Swim/Rowing/Other). Built into the shipped iOS app as an embedded watchOS target.
- HealthKit holds steps/summary workouts/HR; rich set-rep-weight detail lives locally (HealthKit has no schema for it).

## Build

Requires Xcode 16+, Swift 6. Real-device testing needed for HealthKit/CoreBluetooth.

```sh
swift build --package-path CadenceCore
bash scripts/ci-test.sh              # full CadenceCore + CadenceFeatures host tests
make test                            # same package test suite
open Cadence/Cadence.xcodeproj       # iOS app + embedded watchOS app
# CLI build:
bash scripts/xcodebuild-safe.sh -project Cadence/Cadence.xcodeproj -scheme Cadence \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Use SwiftPM for `CadenceCore` and `CadenceFeatures` tests. The Xcode project lists
`CadenceCore` and `CadenceFeatures` as package product schemes, but those schemes
are not configured for Xcode's `test` action. Do not use
`xcodebuild test -scheme CadenceCore` or `xcodebuild test -scheme CadenceFeatures`
in plans or CI; use `swift test --package-path CadenceCore` instead. See
[`docs/TESTING.md`](docs/TESTING.md) for the standard commands and rationale.

Local git hooks are versioned in `scripts/git-hooks`. Install them with
`bash scripts/install-git-hooks.sh`: pre-commit runs only
`bash scripts/ci-test.sh` and never boots a simulator. Pre-push
runs no tests. There is no simulator-based UI test suite in this repo — all
behavioral coverage is the headless `swift test` suite above.

**Build/test turnaround:** PR validation overlaps the host suite and the optimized
iPhone/Watch build in separate runners; `validate` succeeds only when both pass.
The host suite is all Swift Testing, which schedules itself concurrently by
default — there is no serial/parallel mode to choose. The production-flow
harness runs once in the normal suite; its focused command is optional. The
search regression retains all queries with one repetition normally; the
weekly/manual Host Test Benchmark lane runs the full 10-repetition workload and
times the suite twice on one SHA for run-to-run variance.

Preserve local `.build` and repo-specific DerivedData for incremental builds.
CI compiled caches are separated by Xcode/Swift version, architecture, role,
package inputs and commit. Main-branch tests and archiving overlap; export/upload
runs only after both succeed. The signed archive crosses jobs in a run-and-SHA
bound tar artifact retained for one day, preserving symlinks and permissions;
release dSYMs retain their existing 90-day lifetime. TestFlight processing and
tester availability still require App Store Connect reconciliation.

The [shared-light-module research](docs/architecture/shared-light-modules.md)
records a staged way to remove FIT and phone-only dependencies from Watch/widgets
without copying models or workout policies. That extraction is follow-up work.

## TestFlight and human QA

Every successful release upload is reconciled against App Store Connect on a
schedule. Testers should use the issue labels rather than inferring readiness
from a green GitHub workflow: `testflight-uploaded` means Apple accepted the
archive, `testflight-processing` means it is not ready yet, and `ready-for-qa`
means Apple reports that exact version/build as processed (`VALID`).
`testflight-distribution-confirmed` is extra evidence that App Store Connect
reported an assigned tester group. `testflight-access-unverified` only means
the group query was unavailable or empty; it does not prove that TestFlight
cannot install the build.

For a device check, open the issue's **TestFlight availability** comment,
install that exact version/build, follow the issue-specific checklist, and post
the device model, OS, build, scenario, and pass/fail result on the issue. A
failed result is a new repair cycle; only the human owner closes the issue.

## Languages

Cladiron ships in nine locales: English (US), English (UK), Deutsch, Español, Français, Nederlands, Português (Brasil), 简体中文 and 繁體中文. It follows the iPhone's language; to pick a language just for Cladiron, open Settings → Apps → Cladiron → Language. Settings → About → Languages lists every language in the build and links there.

The iPhone app, Apple Watch app, widgets, App Shortcuts phrases, coach explanations and the system permission prompts are translated. Counts use each language's own plural rules. Research paper titles in citations stay in their original English. Exercise names come from DB++ and are localized through `CadenceCore/Sources/CadenceCore/Resources/exercise-names.i18n.json`; names not yet in that file appear in English.

The translations are first drafts: every entry is marked `needs_review` until a native speaker checks it in context. Strings are extracted by the Swift compiler: after changing UI text, run `scripts/sync-localization-catalogs.sh`, add the new keys in every locale, and run `scripts/check-localization-coverage.sh`, which fails on any missing locale, stale key, or hand-built English plural.

## Status

Active development. The app ships a recovery-aware coaching engine with 60 movement-evidence references, 873 DB++ exercises, a normalized 20-muscle ontology, direct/indirect/stabilizer set credits, and five suggested-workout styles. See `docs/CITATIONS.md` for details.

**Coach scientific validation:** A 21-test black-box suite (`CoachScientificValidationTests`) verifies every coaching rule against published exercise science — recovery gates, balance priorities, preference learning, assessment prompts, and edge cases. Each test carries a `CitationRegistry` reference. The full list of validated rules is accessible in-app under Settings → Coach → Coach Methodology. Run with `swift test --package-path CadenceCore --filter CoachScientificValidationTests`.

App Store launch materials live in `docs/app-store/metadata.md` and `docs/app-store/release-checklist.md`. The market positioning and revenue strategy are analyzed in `docs/COMPETITIVE-ANALYSIS.md`.

Built supervised with Claude Code / opencode — see `CLAUDE.md`.

## License and open-project boundary

Cladiron is free and open-source software. Copyright © 2026 Parso
Consulting / John Arley Burns. It is released under the GNU General Public
License v3 or later with the [Cladiron App Store Exception](LICENSE).

The Cladiron source is public so anyone can inspect, modify, and redistribute
the application under those terms. The Cladiron name, icon, logo, screenshots,
and other brand assets remain protected; see [TRADEMARKS.md](TRADEMARKS.md).

Cladiron is built on the open free-exercise-db-plusplus project. The exercise
database, annotations, and related tooling remain freely available for use by
other applications under their own license.

The app pins `free-exercise-db-plusplus` 1.18.2 behind one import boundary. Its FIT/Health interop dependency is resolved transitively; the app's own portability layer keeps JSON as the lossless backup contract.
Cladiron's interface, app-specific coaching composition, persistence, HealthKit
integration, Watch experience, and other application code are covered by the
GPLv3-or-later terms and App Store Exception above.

All users see the coach's **live insights** continuously — real, cited
observations about their own training that update after every workout. The coach
also provides editable prescriptions and adapting weekly plans to every user.
The optional Supporter contribution is an ad-free tip jar and unlocks nothing.

## Automatic TestFlight crash intake

`TestFlight Crash Intake` polls Apple hourly and supports manual dry-run/backfill.
Owner-authored issues are atomically held with `tracking` until usable app crash
evidence is present. Existing controlled issue intake owns repair dispatch; crash
collection never grants CI-maintenance permission or sets human QA labels. The
bootstrap floor is 2026-10-18T20:53:31Z; overlapping scans continue picking up new
and delayed reports automatically. Only sanitized app-owned stack excerpts are
published. Use `TESTFLIGHT_CRASH_INTAKE_ENABLED` and
`TESTFLIGHT_CRASH_AUTOFIX_ENABLED` to control collection and release of new
issues. Already-running repairs need the existing pipeline stop procedure.

Run `ruby scripts/tests/test-testflight-crash-intake.rb` for collector regressions.
The workflow uses existing App Store Connect and owner workflow-token secrets.
Missing logs/symbols remain held and retry hourly; Apple feedback is not a complete
feed of every dashboard crash. Only the owner closes repair issues after device QA.

## Garmin FIT import/export

Completed strength workouts export as a Garmin-valid `.fit` Activity (standard File Id/Session/Lap/Event messages) plus a DB++ developer-field sidecar carrying the exact workout, via `FreeExerciseDBPlusPlusFIT` v1.18.2. Everything runs on-device; no Garmin account, network, or telemetry.

Compatibility contract: re-importing a Cladiron-exported file restores the workout losslessly and atomically (duplicates can be cancelled, kept as a traceable copy, or replaced). A FIT file **without** the sidecar (e.g. a native Garmin recording) is never guessed into a strength workout — strict import reports that the sidecar is required and writes nothing. FIT timestamps are whole seconds, so sub-second precision is not preserved.

## Release scope

Workout logging uses touch controls on iPhone and Apple Watch. Voice/talk logging,
microphone transcription, and raise-to-talk are outside this release. Spoken
workout cues remain available independently.
