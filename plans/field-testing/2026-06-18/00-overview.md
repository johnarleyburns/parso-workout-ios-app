# Cladiron IA + Tests + Coach Wiring + Repositioning — Overview

**Date:** 2026-06-18
**Stream:** `plans/field-testing/2026-06-18/`
**Continuity:** builds on `plans/field-testing/2026-06-06/` (field-testing redesign)

---

## North Star

A genuinely award-worthy, daily-usable app that does something no competitor does: a
private, on-device strength coach whose prescriptions are driven by no-lab fitness tests
the user administers themselves, and whose every recommendation cites readable science.

The bar is Apple Design Award polish (HIG, full accessibility, restrained motion) AND
unique value (the privacy + open-science + field-testable-coach combination no incumbent
offers). Every decision serves "usable and uniquely valuable," not feature count.

## Competitive Wedge

The unoccupied quadrant:

|                     | Account-based | No-account / local |
|---------------------|---------------|--------------------|
| **Closed-source**   | Hevy, Strong, Fitbod, RP, Juggernaut, Boostcamp | — |
| **Open-source/FOSS**| wger (server), FitoTrack (Android) | **Cladiron** |

Cladiron is the only open-source, privacy-first, iPhone-native coach with:
- No accounts, no server, no telemetry — works in airplane mode
- Field-testable fitness battery (no lab) that feeds the coaching engine
- Every prescription + test cites its published source
- Sync only via the user's own iCloud (CloudKit private DB)

## Naming Convention

- **Product name (user-visible):** Cladiron — used in Home title, About, App Store
  listing, on-screen copy, README, all marketing.
- **Internal codename:** Cadence — kept for repo name, Xcode project, scheme, Swift
  package (`CadenceCore`), bundle ID, type names, file names. Do NOT rename these.

## Locked Decisions (from user — do not re-litigate)

1. Tab bar = **Workout / Tests / Progress** (3 tabs).
2. Planning (program selection + routine building) lives INSIDE the Workout tab.
3. Drop Wingate from the default test battery.
4. Naming: "Cladiron" user-visible; "Cadence" internal-only.

## Section Roadmap

| File | Scope |
|------|-------|
| `01-docs-repositioning.md` | P1 — reconcile requirements, rename user-visible strings, privacy NFRs |
| `02-information-architecture.md` | P2 — Workout / Tests / Progress tabs, Library relocation |
| `03-tests-engine.md` | P3 — no-lab battery, on-device cardio math, fitness baseline card |
| `04-coach-wiring.md` | P4 — test baselines → recommendation engine, citations UI |
| `05-built-in-programs.md` | P5 — audit + expand StrengthPresets, planning surface integration |
| `decisions.md` | all binding decisions (locked + new) |

## Cross-Cutting Constraints

- **Schema changes:** additive only (optional/defaulted, no destructive migration).
  CloudKit + existing user data must stay safe.
- **Logic in CadenceCore:** `swift test`-verifiable. UI thin on top.
- **Accessibility:** VoiceOver labels + Dynamic Type on every new/changed view.
- **No project.yml:** `Cadence.xcodeproj` is committed. Add new files to the target in
  the pbxproj directly. Do NOT run xcodegen.
- **Gate each PR:** `cd CadenceCore && swift test` + `xcodebuild -scheme Cadence
  -destination 'platform=iOS Simulator,name=iPhone 16' build` + UI suite.
- **Co-Authored-By trailer** on every commit.

## Phased Rollout

| Phase | Branch | Depends on | Scope | Risk |
|-------|--------|-----------|-------|------|
| **P1** | `p1/docs-repositioning` | `main` | Docs only + string renames. No logic changes. | None |
| **P2** | `p2/information-architecture` | `main` | Tab restructure, Library relocation, exercise browser unification, UI test migration | Medium (UI plumbing) |
| **P3** | `p3/tests-engine` | P2 (needs Tests tab) | Cardio math in CadenceCore, on-device VO2max, fitness baseline card, Wingate gating | Low (pure logic + new views) |
| **P4** | `p4/coach-wiring` | P3 (needs test baselines) | Feed baselines into RecommendationEngine, citations UI | Low (wiring existing pieces) |
| **P5** | `p5/built-in-programs` | P2 (needs planning surface in Workout) | Audit + expand StrengthPresets, planning surface integration | Low |

P1 and P2 are independent of each other (both branch off `main`).
P3 stacks on P2. P4 stacks on P3. P5 stacks on P2.

```
main ──┬── P1 (docs)
       ├── P2 (IA) ──┬── P3 (tests) ── P4 (coach)
       │             └── P5 (programs)
```

## Verification Protocol

Before each PR:
1. `cd CadenceCore && swift test` — must pass
2. `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build` — must pass
3. UI test suite — run, report honestly (environment-flaky vs real failures)
4. Update `current_state.md` at the start of each phase
5. Accessibility audit: every new/changed view has VoiceOver labels + Dynamic Type
