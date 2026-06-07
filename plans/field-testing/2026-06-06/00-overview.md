# Field Testing — 2026-06-06

> First real-gym field test of Cadence (v1, iPhone). The app was used end-to-end
> for a live strength session. This document records the raw observations and
> lays out a **section-by-section redesign plan**. Each section is a separate
> file in this folder so context can be cleared between them.

---

## 1. Raw field notes (verbatim intent)

Captured from the field tester (the primary persona — the Developer-Athlete who
also has low vision and wants legibility from a distance). Paraphrased only for
spelling; intent preserved.

1. **Kill the bottom tab bar.** It takes space and isn't useful. Reach the same
   content through other paths.
2. **Home page should be action-oriented, not a data dashboard.** Apple Health
   already shows steps/activity. Home should offer *actions* — "Start Workout",
   "View Stats" — not re-display health stats.
3. **"Start Workout" → quick workout-type picker** (weight training, running,
   boxing, etc.), and **each type gets its own custom screen**:
   - **Weight training** — already have a logging screen (evolve it).
   - **Running / walking / cycling** — outdoor, GPS path-traced, each its own
     screen.
   - **HIIT** — its own screen with protocol presets (Tabata, Norwegian 4×4),
     and the app runs the timer: e.g. Tabata = 5 min warmup, 8 rounds of
     20s work / 10s rest, 5 min cooldown; Norwegian 4×4 = 4 min effort blocks.
   - **Boxing** — round timer (2 or 3 min rounds, 1 min or 30s rest) with a
     **very prominent full-screen color indicator** visible from far away for
     low-vision users: whole-screen **bright green during work**, **yellow in
     the last 30s**, **flashing in the last 3s**, **red during rest**. The same
     visual system likely helps HIIT too.
4. **Weight training screen needs:**
   - Enter **my own exercises**, not just presets.
   - Drop "templates" — instead just **record workouts** and **reuse an existing
     workout fresh** (start a new session from a past one).
   - **Distinguish equipment** in the defaults:
     cable / barbell / dumbbell / bodyweight / machine (both **isolateral** and
     non-isolateral) / plyometric.
   - **A LOT more default exercises** — exrx.net level of thoroughness.
   - **Fast interactive search** by name and keyword (typing "cable"
     auto-suggests cable exercises). Keywords include **body part**, **actual
     muscle name** (scientific *and* colloquial — "lats", "pecs"), and
     **push/pull**.
   - **Dual units:** show both **lbs and kgs** on weights; let me enter either
     and auto-fill the other.
   - **Partners:** entered at workout time. Often I alternate sets with a friend.
     Let me mark a set as **me (default)** or a named **partner** (up to several
     people working out with me), so I can record their set too — kept **distinct
     from my own** in the health data.
   - **Easy begin/end of a workout**, including a popup to **auto-terminate after
     10 min of no entry** so workouts don't accidentally run forever; and
     **continue workouts across interruptions** (e.g. a phone call) — make sure
     **backgrounding works**.

**Meta-instruction:** "I know this is a lot. It's all critical. Think long and
hard, research top exercise apps / forums / sites, make a detailed
plan/design/mockup doc — but output **section by section** so I can clear context
between sections."

---

## 2. Design principles (derived from the notes)

These guide every section that follows.

- **Action-first, not dashboard-first.** Cadence is a *doing* tool at the gym,
  not a stats mirror of Apple Health. Stats are one tap away, never the front
  door. (Confirmed by competitive/UX research: best apps minimize taps from
  open → start, "one decision per screen", bold CTAs.)
- **Legible from across the room.** The tester has low vision. In-workout
  surfaces (timers, current set, round state) must be readable at arm's length+:
  huge type, whole-screen color states, high contrast, honoring Dynamic Type to
  AX5 (NFR-2). The boxing/HIIT color system is the flagship example.
- **One workout *type*, one purpose-built screen.** No single generic recorder
  stretched across modalities. A shared *session engine* underneath
  (lifecycle, backgrounding, HealthKit save), distinct UIs on top.
- **The user's data, the user's vocabulary.** Custom exercises, colloquial
  muscle names, dual units, named training partners — the model bends to the
  athlete, not the other way around.
- **Survives the real world.** Phone calls, pocket time, forgetfulness. Sessions
  background cleanly and auto-terminate when clearly abandoned.
- **Keep the v1 contracts.** Local-first SwiftData source of truth; only summary
  `HKWorkout` written back; CloudKit-friendly model rules (optionals/defaults, no
  unique constraints, stable UUID + `updatedAt` + `originDevice`); zero
  proprietary deps. (See `CLAUDE.md` / REQUIREMENTS §7.)

---

## 3. Section roadmap (build order)

Each file is self-contained: problem → research → design → data-model deltas →
mockups (ASCII) → implementation steps → testing → open questions. Build in this
order; later sections depend on the engine defined earlier.

| #  | File | Covers (field note) | Depends on |
|----|------|---------------------|------------|
| 00 | `00-overview.md` | This file — notes, principles, roadmap | — |
| 01 | `01-navigation-and-home.md` | Kill tab bar; action-oriented home (#1, #2) | — |
| 02 | `02-start-workout-and-session-engine.md` | Type picker; per-type routing; **session lifecycle** = begin/end, 10-min idle auto-terminate, backgrounding/resume (#3 top-level, #4 lifecycle) | 01 |
| 03 | `03-exercise-database.md` | exrx-level catalog: equipment taxonomy, muscle taxonomy (sci + colloquial), keywords, fast search, seeding (#4 database) | — |
| 04 | `04-weight-training-screen.md` | Custom exercises, reuse-workout (drop templates), dual lb/kg entry, **partners**, set-logging UX (#4 logging) | 02, 03 |
| 05 | `05-cardio-outdoor-gps.md` | Run / walk / cycle GPS screens, live metrics, route map (#3 cardio) | 02 |
| 06 | `06-interval-engine-hiit-boxing.md` | Timer engine; Tabata / Norwegian 4×4 / boxing rounds; **full-screen high-visibility color/flash indicator** (#3 HIIT + boxing) | 02 |
| 07 | `07-data-model-migration-and-rollout.md` | Consolidated schema deltas, CloudKit/migration safety, phased rollout, test matrix | all |

> **How to continue:** clear context, then ask for the next section by number,
> e.g. *"do section 02 from the 2026-06-06 field-testing plan"*. The agent should
> re-read this overview + the relevant current source files before writing.

---

## 4. Cross-cutting decisions (settle once, reuse everywhere)

These recur across sections; deciding them here avoids re-litigating:

- **Tab bar removal → root is the action home.** A single `NavigationStack`
  rooted at the new Home, with everything reachable by push or sheet. Today /
  Trends / Settings become destinations, not tabs. (Detail in §01.)
- **Session engine is shared core.** A `WorkoutLifecycle` concept (start, idle
  watchdog, background continuation, finalize→HealthKit) lives in `CadenceCore`
  so strength, cardio, and interval screens all reuse it. (Detail in §02.)
- **Equipment + muscle taxonomy is data, not enum sprawl.** Equipment becomes a
  first-class typed field on `Exercise`; muscles/keywords are searchable tags
  with a synonym map (sci ↔ colloquial). Large seed shipped as a bundled
  resource, not 500 lines of Swift literals. (Detail in §03.)
- **Units: dual display, kg canonical.** Storage stays kg (already true —
  `SetEntry.weight` is kg). UI gains a dual lb/kg entry control that auto-fills
  the other. No model change needed for display; see §04 for the entry control
  and per-exercise/plate-rounding nuances.
- **Partners as lightweight `Person` + per-set attribution.** A set is attributed
  to the owner (default "me") or a named partner; partner sets are stored but
  **excluded** from the owner's PRs/volume/trends and from HealthKit writeback.
  New `Person` entity + `SetEntry.performedBy`. (Detail in §04, schema in §07.)
- **"Templates" retire in favor of "reuse workout."** Keep `SessionTemplate` in
  the schema for migration safety but remove it from the UI; "Start again from
  this workout" clones a past `WorkoutSession`'s exercises into a fresh session.
  (Detail in §04.)

---

## 5. Cross-cutting open questions (resolve before/while building)

- **Tab bar → what replaces discoverability?** Home action cards + a top-bar
  menu, or a home "more" grid? (Proposed in §01; confirm.)
- **Auto-terminate UX:** silent finalize vs. a "Still training?" prompt with a
  countdown? What happens to the session if the user never responds — saved or
  discarded? (Proposed: prompt, then auto-save. §02.)
- **Partner health data:** the note says "keep distinct in the health data."
  Confirm partner sets are *never* written to the owner's HealthKit (they have no
  Health account on this device). Stored locally for the partner's own record
  only. (Proposed: yes, never written. §04.)
- **Exercise DB size/source:** how many seed exercises is "enough"? exrx.net is a
  reference for *taxonomy depth*, not a copyable dataset (licensing). Propose an
  original ~250–400 entry seed covering their structure. (§03.)
- **Dual units rounding:** when entering lb and storing kg, do we round to a
  clean plate value on display, or show the exact converted value? (§04.)
- **PR/units defaults** (still open from REQUIREMENTS §9): default PR rule
  (1RM est. vs top weight vs volume) and global vs per-exercise unit. Touches
  §04; flag, don't silently decide.

---

## 6. What this plan deliberately does NOT change

- Watch app stays deferred (hardware-blocked) — design for phone; don't break the
  shared core it depends on.
- CloudKit sync stays wired and non-blocking; every schema delta below obeys the
  CloudKit rules so sync keeps working.
- HealthKit contract unchanged: summary `HKWorkout` only; rich detail local.
- No new proprietary dependencies (NFR-6).
