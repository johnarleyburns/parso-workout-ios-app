# CLAUDE.md — Cadence

Project memory for Claude Code. Read `docs/REQUIREMENTS.md` for the full spec; this file is the quick, durable context. Keep it short — prune anything Claude learns on its own.

## What this is
Cadence: an open-source, privacy-first health tracker (free, no accounts, no server). Long-term it's **watch-first** — the Apple Watch as the primary in-workout surface — but see the release scope below.

## Current release (v1) — iPhone-only
The watch app is **deferred** (hardware-blocked for now) but stays in the repo; do **not** prioritize it. v1 ships on iPhone:
- Log **strength** workouts on the phone — the core loop, replaces a hand-kept Gmail draft.
- Read **steps** and ingest **Watch-recorded workouts + HR** from **HealthKit**. This is how watch data appears in v1.
- Review history, PRs, and trends.
CloudKit sync stays wired (single-device iCloud backup + future multi-device) but is non-blocking for v1.

## Stack
- Swift + SwiftUI, **SwiftData** for the local store
- **HealthKit** (steps, workouts, HR, routes, bodyweight)
- **CloudKit private DB** for watch↔phone sync (free; counts against the user's iCloud, not ours)
- **CoreBluetooth** (chest-strap HRM `0x180D`; cardio-machine FTMS `0x1826`)
- **CoreLocation** (geofence + iPhone GPS), **CoreMotion** (activity class), **Swift Charts** (trends)
- Targets: watchOS 10+, iOS 17+

## Architecture (decisions already made — don't re-litigate without asking)
- **`CadenceCore` Swift package** holds the data model, Smart Start ranking, PR logic, and the sync layer. Both app targets depend on it. Write logging logic ONCE here; it's headlessly testable with `swift test`.
- HealthKit has **no schema for sets/reps/weight** — the rich strength model lives in SwiftData locally. Only a *summary* `HKWorkout` is written back to HealthKit.
- **Live HR from the Watch requires an `HKWorkoutSession` on watchOS** (relayed to phone). The iPhone cannot stream the Watch's HR. The chest strap streams to the phone directly over BLE, no watch needed.
- Sync = CloudKit private DB; WatchConnectivity only for live handoff, never as system of record. Every entity carries a stable `UUID` + `updatedAt`; conflicts resolve last-write-wins per set. Handle `CKError.quotaExceeded` gracefully.

## Commands
- Core package: `cd CadenceCore && swift build` / `swift test`
- App: open `Cadence.xcodeproj`; schemes are **Cadence** (iOS) and **Cadence Watch App**. The `.xcodeproj` is committed (created in Xcode, not generated).
- CLI build: `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Real-device runs are required to test HealthKit/CloudKit — the simulator has no real Health data.

## Conventions
- Small, focused commits; one feature per branch; never commit to `main`.
- Reference spec IDs in commits/PRs (e.g. "FR-1 strength logging", "FR-3 steps").
- Follow the phasing in `docs/REQUIREMENTS.md` §8. Build the `CadenceCore` package first.
- Accessibility is not optional: VoiceOver labels + Dynamic Type on every new view (NFR-2).

## Workflow rules for Claude Code
- For any non-trivial feature, **propose a plan first** (plan mode), wait for approval, then implement.
- **Verify before declaring done:** run `swift test` / `xcodebuild` and report the result. Don't claim a feature works without a green build or a test.
- Scope investigations narrowly; ask before large refactors or new dependencies (this repo aims for zero proprietary deps — see NFR-6).
- When a design decision changes, update this file so it stays the source of truth.
