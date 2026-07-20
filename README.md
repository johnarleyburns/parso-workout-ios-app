# Cladiron

A private, open-source, science-based **strength app** for iPhone and Apple Watch. The tracker is **free forever** and open source — logging, history, Progress, Tests, and export are never gated. The **Coach** is a paid product (**Cladiron Pro**). The source is open so you can verify we never track you. Log strength workouts with per-set tracking and partner rotation from your wrist, get cited coaching recommendations grounded in published research, track PRs, and review your training history. Cardio recording and HIIT intervals are supported on both phone and watch. **Companion Apple Watch app included** — run a full "watch-only fitness" session without your phone: strength (with partners, lbs, warm-up/cool-down), HIIT/Boxing with customizable rounds, and cardio (Run/Walk/Cycle indoor & outdoor, Swim with lap counter, Rowing, Other). Live HR streams from the wrist; every completed workout saves to HealthKit for rings credit and auto-ingests back to the phone. Your data stays entirely on-device, with a full JSON export/import so you can back it up or move it to a fresh install at any time.

**Every single coaching output cites published, user-navigable science.** Cladiron never makes a recommendation, insight, warning, or deferred decision without a tappable "The science >" link to the study behind it.

**The coach suggests; it does not proscribe.** Your stated weekly targets always win over the coach's auto-recovery instincts — a rest recommendation is advice attached to your plan, never a silent replacement of it. Every coach surface leaves an escape hatch: pick an alternative, choose any cardio, or build a strength session anyway.

## What it does

- **Recovery-aware coaching engine** — a deterministic, on-device rule engine (not AI) that reads strength, cardio, imported HealthKit workouts, passive HealthKit signals (HRV, resting HR, sleep — fused with, never overriding, your self-report), and optional readiness check-ins. It gates every session through hard eligibility checks (same-lift recovery, pattern/body-part windows, high-fatigue deferral, lower-body collision) before scoring candidates against your balanced weekly plan — incorporating preferences learned from alternatives you've chosen. Then explains exactly what was ruled out, why, and which study backs it.
- **"Why This Today" screen** — every decision is transparent: what you did, Coach's Pick (with alternatives), what was ruled out (with next eligible time), why the winner was chosen, and tappable science citations for every claim. Selecting an alternative teaches Coach your preferences; your learned profile is included in every JSON export.
- **Coach Research Updates + bibliography** — a versioned changelog of the coaching engine, followed by a full bibliography of every study the coach cites, ordered by author. Each entry explains in one line why the coach uses it and links straight to the paper.
- **Strength logging** — per-set weight/reps with inline last-time recall, auto PR detection, rest timer, partner rotation.
- **Prescriptive recommendations** — the coach prescribes concrete next-session targets (double progression, deload, volume adjustment) based on your training goal (strength / hypertrophy / endurance), experience level, and recovery state.
- **Assessments** — strength (e1RM, rep-max, push-up, pull-up, plank, hollow hold) and cardio (VO2max field test, Wingate) battery with longitudinal tracking and retest cadence.
- **Progress dashboard** — science-backed adaptation dashboard: e1RM trends, a PR timeline, a training-consistency heatmap, weekly volume vs landmarks, load intensity vs goal, effort/frequency, test results — every interpretation cites its source with tappable "The science >" links.
- **Exercise library** — 1,000+ exercises from a vendored CC0 database (free-exercise-db) with images, instructions, muscles, and level. Searchable with body-part filters.
- **Workout routines** — Full Body A/B, PHUL (4-day), Arnold Split, StrongLifts 5x5, Push/Pull/Legs, Upper/Lower, Calisthenics, Olympic Lifting, plus user-created templates. Every preset cites the relevant evidence.
- **Cardio recording** — GPS outdoor (run/walk/cycle), indoor recording, swim laps, with live HR from a BLE chest strap (Apple Watch workouts are imported from Health afterward).
- **HIIT intervals** — 7 science-backed protocols (Tabata, Norwegian 4x4, Gibala, SIT, REHIT, 10-20-30, Boxing) with work/rest timing, round bells, and warm-up/cool-down.
- **Companion Apple Watch app** — phone-free training from the wrist: strength with partner rotation, HIIT/Boxing rounds, and a full cardio suite (Run/Walk/Cycle indoor & outdoor, Swim with lap counter, Rowing, Other). Live wrist HR, Health save with rings credit, and automatic sync back to the phone.
- **BLE chest strap** — CoreBluetooth `0x180D` with exponential-backoff reconnection, battery monitoring, and cold-launch auto-reconnect.
- **HealthKit** — reads steps, ingests Watch-recorded workouts + HR, and reads HRV, resting heart rate, sleep, and body weight (on-device only) as a passive-readiness prior the coach fuses with your self-report; writes strength/cardio/interval summaries, HR samples, and GPS routes back to Health.
- **History & trends** — unified strength + cardio history, per-exercise trend charts, workout summary with full per-set detail.
- **Privacy-first** — local-first (SwiftData), no accounts, no third-party server, no ads. A complete, compressed JSON backup (`.json.gz`) export/import lets you back up and move your data (full history + preferences) to a fresh install; imports also accept plain `.json`. That same backup is optionally kept in **your own private iCloud** (never a Cladiron server, never seen by us) and restores automatically on a fresh install — so a lost or replaced phone no longer means a lost training log. This is backup, not live multi-device sync, and it keeps the App Store **Data Not Collected** label.

## Architecture

- `CadenceCore` — Swift package: data model (SwiftData), coaching engine (CoachDecision engine, eligibility gates, weekly planner, insights + recommendations + citations), exercise library, assessment math, PR logic, interval protocols. Both app targets depend on it; headlessly testable with `swift test`.
- `Cadence` — iOS app (primary surface for v1).
- `Cadence Watch App` — a full watchOS companion for phone-free training: strength (with partners), customizable interval workouts, and a complete cardio suite (Run/Walk/Cycle/Swim/Rowing/Other). Built into the shipped iOS app as an embedded watchOS target.
- HealthKit holds steps/summary workouts/HR; rich set-rep-weight detail lives locally (HealthKit has no schema for it).

## Build

Requires Xcode 16+, Swift 6. Real-device testing needed for HealthKit/CoreBluetooth.

```sh
swift build --package-path CadenceCore
swift test --package-path CadenceCore # CadenceCore + CadenceFeatures package tests
make test                            # same package test suite
make all-tests                       # package tests + simulator UI smoke test
open Cadence/Cadence.xcodeproj       # iOS app + embedded watchOS app
# CLI build:
xcodebuild -project Cadence/Cadence.xcodeproj -scheme Cadence \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Use SwiftPM for `CadenceCore` and `CadenceFeatures` tests. The Xcode project lists
`CadenceCore` and `CadenceFeatures` as package product schemes, but those schemes
are not configured for Xcode's `test` action. Do not use
`xcodebuild test -scheme CadenceCore` or `xcodebuild test -scheme CadenceFeatures`
in plans or CI; use `swift test --package-path CadenceCore` instead. See
[`docs/TESTING.md`](docs/TESTING.md) for the standard commands and rationale.

Local git hooks are versioned in `scripts/git-hooks`. Install them with
`bash scripts/install-git-hooks.sh`: pre-commit runs `make pre-commit`
(SwiftPM unit tests), and pre-push runs `make pre-push` (unit tests plus the
simulator smoke test).

**Timing notes:** `swift test` takes ~50s, `xcodebuild build` ~20s, and the
full pre-push sequence (build-for-testing + smoke test) takes ~2-3 min.
When scripting `git push`, use a timeout of at least 300s to allow the
pre-push hook to complete. CI workflows should budget ≥5 min for the
core-tests job and ≥10 min for the smoke/xcodebuild jobs.

## Status

Active development. The app ships a full recovery-aware coaching engine with 30+ peer-reviewed citations, 1,000+ exercises, and 28+ preset routines. See `PLAN_STATUS.md` for detailed phase tracking and `docs/CITATIONS.md` for the evidence base.

**Coach scientific validation:** A 21-test black-box suite (`CoachScientificValidationTests`) verifies every coaching rule against published exercise science — recovery gates, balance priorities, preference learning, assessment prompts, and edge cases. Each test carries a `CitationRegistry` reference. The full list of validated rules is accessible in-app under Settings → Coach → Coach Methodology. Run with `swift test --package-path CadenceCore --filter CoachScientificValidationTests`.

App Store launch materials live in `docs/app-store/metadata.md` and `docs/app-store/release-checklist.md`. The market positioning and revenue strategy are analyzed in `docs/COMPETITIVE-ANALYSIS.md`.

Built supervised with Claude Code / opencode — see `CLAUDE.md`.

## License

**GPLv3** — see [LICENSE](LICENSE). The Cladiron source code is free software
under the GNU General Public License v3.0.

The **"Cladiron" name, app icon, and brand assets are trademarks** and are *not*
covered by the GPL — see [TRADEMARKS.md](TRADEMARKS.md). Forks must use their own
name and icon.

As the sole copyright holder, John Arley Burns grants an **App Store exception**
(see [LICENSE](LICENSE)) permitting distribution of this software through the
Apple App Store under Apple's standard terms, notwithstanding any conflict with
sections 6 and 12 of the GPL. This exception applies only to distribution by the
copyright holder.

Cladiron is open source so users can independently verify there is no tracking,
no telemetry, and no account or server — the privacy claims are auditable.
Purchasing **Cladiron Pro** on the App Store funds continued development. The free
app is complete on its own; Pro adds the coaching layer (see below).

Free users see the coach's **live insights** continuously — real, cited
observations about their own training that update after every workout. What Pro
unlocks is the **prescription**: the exact sets, reps, and load the coach would
have you do next, plus the adapting weekly plan. The free experience is never an
ad — the upsell only surfaces occasionally, while the insights are always on.
