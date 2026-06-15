# Cadence

A free, open-source, **watch-first** health tracker for iPhone + Apple Watch. Log strength workouts from your wrist (Digital Crown), record cardio with accurate heart rate — from the Watch *or* a Bluetooth chest strap when you don't have it — and keep your daily steps front and center. Your data stays in your own iCloud.

> Working title — rename freely.

## Why
No free app does all of this in one place: detailed per-set strength logging with PR and last-time recall, Apple Watch cardio with heart rate, **watchless** cardio via a chest strap, and prominent daily steps. Cadence is that app, built to Apple's Human Interface Guidelines.

## Features
- **Wrist-first logging** — dial weight/reps with the Digital Crown; last-time and PR shown inline.
- **Cardio with real HR** — from the Watch (`HKWorkoutSession`) or a BLE chest strap (`0x180D`).
- **Smart Start** — a ranked best-guess of your next workout from your habits, time, and location; sensors (FTMS machines, NFC tags) just pre-tick a row. Works fully offline with none of them.
- **Steps up front** — read straight from HealthKit, no watch required.
- **Yours** — local-first, synced across your devices via your private iCloud. No accounts, no server, no ads.

## Architecture
- `CadenceCore` — Swift package: data model (SwiftData), Smart Start ranking, PR logic, CloudKit sync. Shared by both apps.
- `CadenceWatch` — watchOS app (primary in-workout surface).
- `CadenceiOS` — iOS app (review hub + watchless logging).
- HealthKit holds steps/summary workouts/HR; rich set–rep–weight detail lives locally (HealthKit has no schema for it).

See [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) for the full spec and [`docs/design/mockups.html`](docs/design/mockups.html) for the UI mockups.

## Build
Requires Xcode 16+, an Apple Developer account (CloudKit/HealthKit need real-device testing), and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cd CadenceCore && swift test     # core logic
xcodegen generate                # build the Xcode project from project.yml
open Cadence.xcodeproj
```

## Status
Early development. Built supervised with Claude Code — see `CLAUDE.md`.

The app is pivoting to a focused, science-based **strength coach** (see the
strength-pivot plan docs). As part of that, CrossFit was removed; its full
pre-removal code is preserved in the annotated git tag **`crossfit-preserved-v1`**
(recoverable base for a possible future standalone CrossFit app). Boxing remains
as a cardio/interval workout.

## License
MIT — see [LICENSE](LICENSE).
