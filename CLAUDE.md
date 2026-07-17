# CLAUDE.md — Cadence

Project memory for Claude Code. Read `docs/REQUIREMENTS.md` for the full spec; this file is the quick, durable context. Keep it short — prune anything Claude learns on its own.

## Naming

- **Product name (user-visible):** Cladiron — Home title, About, App Store, on-screen copy, README.
- **Internal codename:** Cadence — repo, Xcode project, scheme, Swift package (`CadenceCore`), bundle ID, type names. Do NOT rename these.

## What this is
Cladiron: an open-source, privacy-first, iPhone-native **strength coach**. The tracker is free forever; the Coach is a paid product (see Monetization below). Its prescriptions are driven by no-lab fitness tests the user administers themselves, and every recommendation cites readable, published science. Cardio is secondary/capture-only. No accounts, no server, no telemetry.

## Monetization

The tracker is **free forever** — logging, history, Progress, Tests, and export
are never gated. **Cladiron Pro** gates the Coach's *prescription* (what to do);
the Coach's *insight* (what it noticed) stays free.

Products: `guru.parso.cladiron.pro.annual` / `.monthly` / `.lifetime`, plus
tip-jar consumables that unlock nothing. StoreKit 2 only — no RevenueCat, no
server, no third-party SDKs (this is a privacy requirement, not a shortcut).
Entitlement resolution lives in `CadenceCore/ProEntitlement.swift`; the gate is
`CoachSurfacePresenter`, **not** `CoachGate` (which is dead code — Phase 2
deletes it).

## Information Architecture (3 tabs)
- **Workout** (Home) — strength-first hero, secondary cardio, coach cards/insights, **Programs & Routines** entry (planning surface lives here).
- **Tests** — no-lab fitness assessment battery, "Your Fitness" baseline card, protocol instructions, cited sources.
- **Progress** — training history, PR timeline, per-exercise trends, assessment trends, consistency heatmap.

## Current release (v1) — iPhone-only
The watch app is **deferred** (hardware-blocked for now) but stays in the repo; do **not** prioritize it. v1 ships on iPhone:
- Log **strength** workouts on the phone with **coaching** — the core loop.
- Run a **no-lab fitness test battery** whose baselines feed the coach.
- Read **steps** and ingest **Watch-recorded workouts + HR** from **HealthKit**. The coach also reads **HRV, resting HR, sleep, and bodyweight** (read-only, on-device) as a passive-readiness prior fused with self-report.
- Review history, PRs, trends, and assessment results.
- Follow **built-in programs** (5/3/1, PPL, 5x5, splits, calisthenics, Olympic).
Cladiron is **local-first — no live cloud sync**. Data portability is handled by a complete JSON **export/import** (full workout history + assessments + all preferences), so a user can back up and move to a fresh install losslessly. As insurance against a lost/replaced phone, that same export blob is **automatically backed up to the user's *own* private CloudKit database** (D5) and restored on a fresh install — Apple is the processor, Cladiron never sees it, so the **Data Not Collected** label is unaffected.

## Stack
- Swift + SwiftUI, **SwiftData** for the local store
- **HealthKit** (steps, workouts, HR, routes; HRV, resting HR, sleep, bodyweight for passive readiness — read-only, on-device)
- **No live cloud sync** — local-first; data portability is JSON export/import, plus an automatic backup of that export blob to the user's own private CloudKit (D5). No third-party server.
- **CoreBluetooth** (chest-strap HRM `0x180D`; cardio-machine FTMS `0x1826`)
- **CoreLocation** (geofence + iPhone GPS), **CoreMotion** (activity class), **Swift Charts** (trends)
- Targets: watchOS 10+, iOS 17+

## Architecture (decisions already made — don't re-litigate without asking)
- **`CadenceCore` Swift package** holds the data model, Smart Start ranking, PR logic, and the export/import layer. Both app targets depend on it. Write logging logic ONCE here; it's headlessly testable with `swift test`.
- HealthKit has **no schema for sets/reps/weight** — the rich strength model lives in SwiftData locally. Only a *summary* `HKWorkout` is written back to HealthKit.
- **Live HR from the Watch requires an `HKWorkoutSession` on watchOS** (relayed to phone). The iPhone cannot stream the Watch's HR. The chest strap streams to the phone directly over BLE, no watch needed.
- **No live cloud sync.** Data portability is JSON export/import: every entity carries a stable `UUID` so import merges idempotently by id. The export blob is additionally auto-backed-up to the user's private CloudKit and restored on a fresh install (D5) — this is *not* live multi-device sync. WatchConnectivity is only for live handoff, never a system of record.

## Commands
- Core package: `cd CadenceCore && swift build` / `swift test`
- App: open `Cadence.xcodeproj`; schemes are **Cadence** (iOS) and **Cadence Watch App**. The `.xcodeproj` is committed (created in Xcode, not generated).
- CLI build: `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Real-device runs are required to test HealthKit — the simulator has no real Health data.

## Conventions
- Small, focused commits; one feature per branch; push to main when verified.
- Reference spec IDs in commits/PRs (e.g. "FR-1 strength logging", "FR-3 steps").
- Follow the phasing in `docs/REQUIREMENTS.md` §8. Build the `CadenceCore` package first.
- Accessibility is not optional: VoiceOver labels + Dynamic Type on every new view (NFR-2).
- **Logic goes in `CadenceFeatures`, not in a `View`.** Views take a prepared
  state struct / view-model and render it; the logic is unit-tested in
  `CadenceFeaturesTests` (headless `swift test`). `CadenceFeatures` imports only
  Foundation + SwiftData + Observation — if an extraction wants a `Color`/`View`,
  return a semantic enum and let the view map it. The XCUITest suite is a fixed
  ~10-test smoke gate and **does not grow** — new coverage is a `swift test`.
  `scripts/check-test-pyramid.sh` (CI) enforces all three: the import ban, the
  ≤12 UI-test cap, and the 400-LOC-per-Features-file budget (grandfathered large
  views may only shrink).

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

## HARD RULE: The coach suggests, it does not proscribe (NFR-8)
The user's stated schedule targets always win over auto-recovery. Recovery/lighter-day
outputs are advice *attached to* the plan (e.g. `PlannedSession.adviceNote`/
`recommendsLighter`), never a silent replacement of a requested session. Every coach
surface must leave an escape hatch (alternatives, full cardio picker, strength-anyway).

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
  migration) to keep the local store + older JSON exports working.
- **Verify, then commit/push/PR.** `swift test` is the reliable gate (Mac
  toolchain). The `xcodebuild` UI suite is the integration gate but can be flaky
  on a degraded simulator — if launches balloon (~45s, `no debugger version`),
  restart CoreSimulator (`killall -9 com.apple.CoreSimulator.CoreSimulatorService`)
  and re-run; report honestly which tests are real vs environment-flaky.
- Reference spec IDs (FR-x, field-testing §n) and end commits with the
  Co-Authored-By trailer.

## Post-task checklist (MANDATORY — NEVER skip after completing a task)
Once the work is verified (green build + tests), execute these steps in order.
**This checklist is NOT optional.** Every task MUST end with a commit, merge,
and push unless the user explicitly says otherwise.

1. **Audit plan vs implementation** — re-read the plan (if one exists) and check
   every acceptance criterion, data-model change, and UI requirement against
   the shipped code. Fix any discrepancies before committing.
2. **Update `current_state.md`** with what shipped, new test counts, and any
   intentional deviations from the plan.
3. **Update README** if the feature changes user-visible behavior, setup steps,
   or the high-level description of the app.
4. **Stage + commit** all changes with a concise, conventional-commit message
   (e.g. `feat: coach why-this-today + preference learning`). Include changed
   files and new files. Never commit before verifying.
5. **Merge to `main`** if not already there (`git checkout main && git merge --ff-only <branch>`).
   If already on `main`, commit directly to `main`.
6. **Push** (`git push origin main`).
7. **Monitor CI** — check `git log --oneline -1` to confirm the push SHA, then
   use `gh run list --branch main --limit 1` to watch the workflow.
8. **Report the commit SHA and CI status** to the user.
