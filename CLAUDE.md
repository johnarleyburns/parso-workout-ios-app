# CLAUDE.md — Cadence

Project memory for Claude Code. Read `docs/REQUIREMENTS.md` for the full spec; this file is the quick, durable context. Keep it short — prune anything Claude learns on its own.

## Naming

- **Product name (user-visible):** Cladiron — Home title, About, App Store, on-screen copy, README.
- **Internal codename:** Cadence — repo, Xcode project, scheme, Swift package (`CadenceCore`), bundle ID, type names. Do NOT rename these.

## What this is
Cladiron: a free, open-source, privacy-first, iPhone-native **strength coach**. Its prescriptions are driven by no-lab fitness tests the user administers themselves, and every recommendation cites readable, published science. Cardio is secondary/capture-only. No accounts, no server, no telemetry.

## Information Architecture (3 tabs)
- **Workout** (Home) — strength-first hero, secondary cardio, coach cards/insights, **Programs & Routines** entry (planning surface lives here).
- **Tests** — no-lab fitness assessment battery, "Your Fitness" baseline card, protocol instructions, cited sources.
- **Progress** — training history, PR timeline, per-exercise trends, assessment trends, consistency heatmap.

## Current release (v1) — iPhone-only
The watch app is **deferred** (hardware-blocked for now) but stays in the repo; do **not** prioritize it. v1 ships on iPhone:
- Log **strength** workouts on the phone with **coaching** — the core loop.
- Run a **no-lab fitness test battery** whose baselines feed the coach.
- Read **steps** and ingest **Watch-recorded workouts + HR** from **HealthKit**.
- Review history, PRs, trends, and assessment results.
- Follow **built-in programs** (5/3/1, GZCLP, nSuns, PPL, 5x5, splits, calisthenics, Olympic).
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

## HARD RULE: Every coaching output MUST cite science
Cladiron never makes a single recommendation, insight, warning, deferred decision, or
scoring rationale that isn't backed by cited, user-navigable scientific literature.
Every screen that surfaces coach output MUST display tappable citations:

- Use `CitationRegistry.citation(forId:)` to resolve string IDs to `Citation` objects.
- Render every citation with `CitationLink` (standard or `compact: true` for "The science >").
- Never display raw citation IDs (e.g. `"parejaBlancoRecovery2020"`) to the user.
- If a new coaching output adds a `citationIds` field, it MUST be resolved and rendered in the UI.
- Citation tests must fail when a user-visible science claim references a missing ID.
- `CitationRegistry.all` and `docs/CITATIONS.md` must stay in sync — every ID in the registry
  must have a corresponding entry in CITATIONS.md explaining how it's used.

## Workflow rules for Claude Code
- For any non-trivial feature, **propose a plan first** (plan mode), wait for approval, then implement.
- **Verify before declaring done:** run `swift test` / `xcodebuild` and report the result. Don't claim a feature works without a green build or a test.
- Scope investigations narrowly; ask before large refactors or new dependencies (this repo aims for zero proprietary deps — see NFR-6).
- When a design decision changes, update this file so it stays the source of truth.

## Dev methodology (plan → implement, phase by phase)
This is how large bodies of work (e.g. the field-testing redesign) are run. Mirror it.

**1. Plan to disk first, section by section.**
- For a big request, write design docs under `plans/<topic>/<date>/` — one file per
  section (`00-overview.md` = raw notes + principles + roadmap + cross-cutting
  decisions; then one file per feature area). Research (web, competitors, the
  existing code) *before* writing each section; ground every section in the real
  files it will touch.
- Each design section follows: problem → what the code does today → research
  signal → design (with ASCII mockups) → data-model deltas → implementation steps
  → testing → open questions.
- Capture every decision that needs the user in a **decision sheet**; once
  answered, record verbatim in `decisions.md`. Don't re-litigate settled
  decisions.
- A final section consolidates schema deltas, migration safety, and a **phased
  rollout table** (one branch+PR per phase, with dependencies).

**2. Implement phase by phase, one PR each.**
- Before starting a phase: update `current_state.md` (and this methodology if it
  changed) so progress is trackable, then begin.
- Branch per phase. If a phase depends on earlier un-merged phases, **stack** its
  branch on them (branch off the dependency, merge siblings in) rather than
  branching off `main` — keeps the dependency chain buildable. Independent phases
  branch off `main`.
- Logic lives in `CadenceCore` (pure, `swift test`-verifiable); UI is thin on top.
- Schema changes are **additive only** (optional/defaulted, no destructive
  migration) to keep CloudKit + existing data working.
- **Verify, then commit/push/PR.** `swift test` is the reliable gate (Mac
  toolchain). The `xcodebuild` UI suite is the integration gate but can be flaky
  on a degraded simulator — if launches balloon (~45s, `no debugger version`),
  restart CoreSimulator (`killall -9 com.apple.CoreSimulator.CoreSimulatorService`)
  and re-run; report honestly which tests are real vs environment-flaky.
- Reference spec IDs (FR-x, field-testing §n) and end commits with the
  Co-Authored-By trailer.
