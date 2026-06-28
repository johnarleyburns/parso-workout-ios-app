# Cladiron

A free, open-source, science-based **strength coach** for iPhone. v1 is iPhone-first: log strength workouts with per-set tracking, get cited coaching recommendations grounded in published research, track PRs, and review your training history. Cardio recording and HIIT intervals are supported as a secondary capability. **There is no companion Apple Watch app at this time** — the iPhone imports Watch-recorded workouts and heart rate from Apple Health, and a native watchOS app is only a possible future addition. Your data stays on-device and in your own iCloud.

**Every single coaching output cites published, user-navigable science.** Cladiron never makes a recommendation, insight, warning, or deferred decision without a tappable "The science >" link to the study behind it.

## What it does

- **Recovery-aware coaching engine** — a deterministic, on-device rule engine (not AI) that reads strength, cardio, imported HealthKit workouts, and optional readiness check-ins. It gates every session through hard eligibility checks (same-lift recovery, pattern/body-part windows, high-fatigue deferral, lower-body collision) before scoring candidates against your balanced weekly plan — incorporating preferences learned from alternatives you've chosen. Then explains exactly what was ruled out, why, and which study backs it.
- **"Why This Today" screen** — every decision is transparent: what you did, Coach's Pick (with alternatives), what was ruled out (with next eligible time), why the winner was chosen, and tappable science citations for every claim. Selecting an alternative teaches Coach your preferences; your learned profile is included in every JSON export.
- **Strength logging** — per-set weight/reps with inline last-time recall, auto PR detection, rest timer, partner rotation.
- **Prescriptive recommendations** — the coach prescribes concrete next-session targets (double progression, deload, volume adjustment) based on your training goal (strength / hypertrophy / endurance), experience level, and recovery state.
- **Assessments** — strength (e1RM, rep-max, push-up, pull-up, plank, hollow hold) and cardio (VO2max field test, Wingate) battery with longitudinal tracking and retest cadence.
- **Progress dashboard** — science-backed adaptation dashboard: e1RM trends, weekly volume vs landmarks, load intensity vs goal, effort/frequency, test results — every interpretation cites its source with tappable "The science >" links.
- **Exercise library** — 1,000+ exercises from a vendored CC0 database (free-exercise-db) with images, instructions, muscles, and level. Searchable with body-part filters.
- **Workout routines** — Full Body A/B, PHUL (4-day), Arnold Split, StrongLifts 5x5, Push/Pull/Legs, Upper/Lower, Calisthenics, Olympic Lifting, plus user-created templates. Every preset cites the relevant evidence.
- **Cardio recording** — GPS outdoor (run/walk/cycle), indoor recording, swim laps, with live HR from a BLE chest strap (Apple Watch workouts are imported from Health afterward).
- **HIIT intervals** — 7 science-backed protocols (Tabata, Norwegian 4x4, Gibala, SIT, REHIT, 10-20-30, Boxing) with work/rest timing, round bells, and warm-up/cool-down.
- **No companion Apple Watch app (yet)** — the current release is iPhone-only. Apple Watch workouts and heart rate are imported from Apple Health after the session. A native watchOS app (live HR relay + on-watch logging) is a potential future direction, not part of this release.
- **BLE chest strap** — CoreBluetooth `0x180D` with exponential-backoff reconnection, battery monitoring, and cold-launch auto-reconnect.
- **HealthKit** — reads steps, ingests Watch-recorded workouts + HR; writes strength/cardio/interval summaries, HR samples, and GPS routes back to Health.
- **History & trends** — unified strength + cardio history, per-exercise trend charts, PR timeline, consistency heatmap, workout summary with full per-set detail.
- **Privacy-first** — local-first (SwiftData), optional iCloud sync (CloudKit private DB, your quota). No accounts, no server, no ads.

## Architecture

- `CadenceCore` — Swift package: data model (SwiftData), coaching engine (CoachDecision engine, eligibility gates, weekly planner, insights + recommendations + citations), exercise library, assessment math, PR logic, interval protocols. Both app targets depend on it; headlessly testable with `swift test`.
- `Cadence` — iOS app (primary surface for v1).
- `Cadence Watch App` — a watchOS target kept in the repo for a possible future version. It is **not part of the current release** and is not built into the shipped iOS app.
- HealthKit holds steps/summary workouts/HR; rich set-rep-weight detail lives locally (HealthKit has no schema for it).

## Build

Requires Xcode 16+, Swift 6. Real-device testing needed for HealthKit/CloudKit/CoreBluetooth.

```sh
cd CadenceCore && swift build        # core package
cd CadenceCore && swift test         # 250+ tests
open Cadence/Cadence.xcodeproj       # iOS app (watchOS target in-repo, not in the current release)
# CLI build:
xcodebuild -project Cadence/Cadence.xcodeproj -scheme Cadence \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Status

Active development. The app ships a full recovery-aware coaching engine with 30+ peer-reviewed citations, 1,000+ exercises, and 28+ preset routines. See `PLAN_STATUS.md` for detailed phase tracking and `docs/CITATIONS.md` for the evidence base.

Built supervised with Claude Code / opencode — see `CLAUDE.md`.

## License

MIT — see [LICENSE](LICENSE).
