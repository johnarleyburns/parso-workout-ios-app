# Cladiron — Requirements & Use Cases

> **Product name (user-visible): Cladiron.** Internal codename: Cadence — used for the repo, Xcode project, scheme, Swift package (`CadenceCore`), bundle ID, and type names.

**Status:** Legacy v1 requirements; superseded by `docs/plans/cladiron-mvp-revised/CLADIRON_PLATFORM_SPEC.md` · **Platforms:** iPhone (iOS 17+) + embedded watchOS 10+ companion app · **License:** GPLv3-or-later with the Cladiron App Store Exception · **Distribution:** TestFlight + App Store

> **v1 release scope:** log strength on the phone with coaching; read steps + ingest Watch-recorded workouts/HR from HealthKit; run a no-lab fitness test battery that feeds the coach; review history, PRs, and trends; train phone-free from the Watch (FR-8, shipped 2026-07-17: strength with partners, HIIT, cardio suite, live wrist HR). FTMS/NFC and Smart Start sensors move to later releases — see §9.

---

## 1. Vision & Goals

Cladiron is an open-source, privacy-first, iPhone-native **strength coach**. The tracker is free forever; the Coach is a paid product (**Cladiron Pro**). It is a no-account, on-device coaching app whose prescriptions are driven by field-testable fitness assessments the user administers themselves, and whose every recommendation cites readable, published science. Cladiron is built on the open `free-exercise-db-plusplus` project; the exercise database, annotations, and related tooling remain freely available for other applications under their own license.

**The competitive wedge:**

|                     | Account-based | No-account / local-first |
|---------------------|---------------|--------------------|
| **Closed-source**   | Hevy, Strong, Fitbod, RP, Juggernaut, Boostcamp | — |
| **Privacy-first / on-device** | wger (server), FitoTrack (Android) | **Cladiron** |

**Primary goals**

- **Science-based strength coach:** a deterministic, on-device expert engine that reads training history and field-test baselines to produce cited, concrete prescriptions. Not AI — a rule engine grounded in published exercise-science research.
- **Field-testable fitness:** a no-lab assessment battery (requiring only an ordinary gym, a field/track, the app's stopwatch, and optionally a BLE chest strap) whose results feed the coaching engine. No wearable or lab gear required for the core battery.
- **Auditable science:** every prescription and every test cites its published source via the built-in CitationRegistry. The user can always see *why*.
- **Built-in established programs:** 5/3/1, PPL, 5x5, splits, calisthenics, Olympic lifting, and more for self-directed users who prefer a published program over coach-generated prescriptions.
- **Strength-first, cardio secondary:** strength logging and coaching is the core loop. Cardio is capture-only (ingest Watch workouts from HealthKit, record with iPhone GPS or chest strap) — not coached in v1.
- **Privacy by design:** no accounts, no developer-operated server, no telemetry, no third-party SDKs. Works in airplane mode. Data persists locally and mirrors through the user's private iCloud; portability is also available through JSON export/import.
- **Apple Design Award polish:** HIG-native, fully accessible (VoiceOver, Dynamic Type, Reduce Motion), restrained motion, inclusive design.

**Non-goals (for v1)**

- Social feeds, coaching marketplaces, or AI form-checking.
- Android or web clients.
- Nutrition/macro tracking (may sync bodyweight only).
- Cloud accounts or server-side storage.
- Cardio coaching (cardio capture only; coaching is strength-focused).

## 2. Personas

- **The Developer-Athlete (primary):** trains with weights 3-5x/week, runs/cycles/boxes/swims, cares about PRs and trends, sometimes leaves the watch at home. Wants data ownership, cited science, and a clean tool.
- **The Quantified Beginner (secondary):** wants steps + simple workout logging without paying or being upsold. Benefits from the coach's guidance and built-in programs.

## 3. Glossary

- **Set:** one bout of an exercise — a weight x reps pair (optionally RPE/notes).
- **PR:** personal record for an exercise (heaviest weight, best estimated 1RM, or best volume).
- **Last-time:** the most recent prior performance of the same exercise, shown inline while logging.
- **Session:** a dated collection of exercises and their sets (a "workout").
- **HRM:** Bluetooth LE heart-rate monitor (chest strap or armband) exposing the standard Heart Rate Service (0x180D).
- **Assessment:** a standardized fitness test from the battery (e.g., Cooper 12-min run, push-up max, e1RM) that produces a measurable baseline.
- **Baseline:** the user's current assessment results, used by the coach to prescribe loads and targets.

---

## 4. Information Architecture

Three tabs:

### Workout (Home)
The primary surface. Hero action starts a strength workout; secondary action starts cardio. Displays the coach's recommendations (CoachCardView) and insights. Contains a **Programs & Routines** entry that opens the planning surface (routine browser, preset programs, user templates, template editor).

### Tests
The no-lab fitness assessment battery. Lists all available tests grouped by category (Strength, Strength Endurance, Cardio). Each test links to its protocol, recording interface, and cited source. A **"Your Fitness" baseline card** summarizes current 1RMs, VO2max, endurance benchmarks, and trend arrows with "last tested / re-test due" nudges.

### Progress
Training history (strength + cardio sessions), PR timeline, consistency heatmap, per-exercise trends, and assessment/test-result trends over time.

Planning (program selection + routine building) lives **inside the Workout tab**, not its own tab.

---

## 5. Functional Requirements

### FR-1 Strength logging
- FR-1.1 Create a session and add exercises from a searchable library (with custom exercises and categories: push/pull/legs, or muscle group).
- FR-1.2 Log multiple sets per exercise; each set captures weight, reps, optional RPE and note.
- FR-1.3 While logging a set, display the matching **last-time** set and the current **PR** inline.
- FR-1.4 Auto-detect and flag a new PR (configurable: 1RM estimate, top weight, or top volume).
- FR-1.5 Rest timer between sets, auto-startable on set completion.
- FR-1.6 Reusable session templates (e.g., "Push Day").
- FR-1.7 Edit/delete past sets and sessions.

### FR-2 Cardio tracking (capture-only)
- FR-2.1 Automatically ingest Apple Watch workouts (running, cycling, swimming, boxing/HIIT) and their heart-rate samples from HealthKit; no double-entry.
- FR-2.2 Record an **iPhone-only** outdoor workout using GPS for route/distance/pace (running, cycling) and a manual timer for indoor (boxing, etc.).
- FR-2.3 Pair a **Bluetooth chest strap** and capture live heart rate during any iPhone-recorded workout (see FR-4.4).
- FR-2.4 Show live metrics during recording: elapsed time, distance/pace, current HR, HR zone, calories estimate.
- FR-2.5 Save recorded workouts back to HealthKit as `HKWorkout` (with route and HR samples) so they appear system-wide and close Activity rings.

### FR-3 Daily activity & steps
- FR-3.1 Read daily step count from HealthKit (iPhone pedometer works without a watch).
- FR-3.2 Surface steps prominently on the home screen with a goal ring and 7-day trend.
- FR-3.3 Show flights climbed, walking/running distance, and active energy alongside steps.

### FR-4 Data, HealthKit & sensors
- FR-4.1 Request least-privilege HealthKit read/write authorization with clear in-context priming.
- FR-4.2 Local-first storage (SwiftData) as the source of truth for the rich strength model HealthKit cannot represent.
- FR-4.3 Write summary strength workouts to HealthKit for unified history; keep detailed set data local.
- FR-4.4 **Chest strap:** discover, connect, and subscribe to a BLE HRM via 0x180D; reconnect automatically; surface battery and signal status; persist a remembered device.
- FR-4.5 (superseded) The former local-only rule was replaced by local SwiftData mirrored through the user's private iCloud. Complete JSON export/import remains required (FR-6).

### FR-5 History, PRs & trends
- FR-5.1 Per-exercise history list and trend chart (top weight, est. 1RM, volume over time).
- FR-5.2 PR timeline per exercise and a global "recent PRs" view.
- FR-5.3 Cardio history with HR overlay, pace splits, and route map.
- FR-5.4 Calendar/heatmap of training consistency.

### FR-6 Migration & export
- FR-6.1 One-time importer that parses the existing Gmail-draft format into the local store.
- FR-6.2 Full data export (JSON/CSV) and import — the user owns and can leave with their data.

### FR-7 Smart Start (best-guess preselect, graceful degradation)
**Core principle:** the ranked best-guess list works with **zero** special hardware. Sensors are strictly additive.

- FR-7.1 Present a ranked best-guess list of likely workouts; one tap launches.
- FR-7.2 Ranking uses always-available signals: history/habit, time context, location (if permitted), motion (if permitted), heart rate (if connected).
- FR-7.3 Top guess never auto-committed without confirmation.
- FR-7.4 Progressive enhancement: FTMS/NFC/beacon are optional additions.
- FR-7.5 Learning: confirmed selections feed back to improve ranking.
- FR-7.6 Manual override always present.
- FR-7.7 Cold start: sensible category defaults.

### FR-8 Apple Watch (SHIPPED 2026-07-17, ahead of the original v2 phasing)
- FR-8.1 Embedded watchOS companion app for phone-free wrist workouts: strength
  (partner rotation, warm-up/cool-down), HIIT/Boxing rounds, and cardio
  (run/walk/cycle indoor & outdoor, swim with lap counter, rowing, other).
- Live wrist HR via `HKWorkoutSession`; workouts save to HealthKit (rings
  credit) and relay to the phone over WatchConnectivity for auto-ingest.
- Remaining W5 backlog (Resume, complication, routes, smart swap) tracked in
  `plans/watch-app/2026-07-17/`.

### FR-9 Cross-device portability & roles
- FR-9.1 (superseded) The store is local-first and mirrors through private iCloud; JSON export/import remains the explicit portable backup (FR-6). WatchConnectivity handles live handoff and durable completion delivery.
- FR-9.2 Every entity carries a stable UUID so export/import merges idempotently by id.
- FR-9.3 Phone is the analysis surface; watch is the in-workout surface (future).
- FR-9.4 (removed) Cloud sync is not part of the app.

### FR-10 Fitness assessment battery (Tests)
**Hard constraint:** all tests require only an ordinary gym + a field/track + the app's stopwatch + optionally a BLE chest strap (0x180D). No lab gear.

- FR-10.1 **Strength assessments:** e1RM (estimated one-rep max), rep-max, push-up max, pull-up max, bodyweight squat max, plank hold, hollow hold.
- FR-10.2 **Cardio assessments (on-device computation):**
  - Cooper 12-minute run: VO2max = (distance_m - 504.9) / 44.73 (Cooper 1968).
  - 1.5-mile run: VO2max via the standard published regression.
  - Rockport 1-mile walk: VO2max from age, sex, weight, walk time, ending HR (Kline et al. 1987). Uses chest strap or manual HR.
  - Queens College 3-min step test (optional): recovery HR to VO2max (McArdle et al. 1972).
- FR-10.3 Each assessment has a self-contained protocol description (the app gives the number — no external calculators).
- FR-10.4 Each assessment cites its published source via CitationRegistry.
- FR-10.5 **"Your Fitness" baseline card:** current 1RMs, VO2max with fitness-category label (ACSM normative tables), endurance benchmarks, each with trend pill and "re-test due" nudge.
- FR-10.6 Assessment trends surfaced in the Progress tab.
- FR-10.7 Wingate kept as an assessment type but gated behind "Advanced — requires an ergometer" (not in the default battery).

### FR-11 In-app citations
- FR-11.1 "Why this?" affordance on coach prescriptions (CoachCardView) opens the cited source(s).
- FR-11.2 Each test links its cited source in the detail view.
- FR-11.3 CitationRegistry provides structured citation data (authors, year, title, source, URL).
- FR-11.4 docs/CITATIONS.md maintained as a human-readable reference for the full evidence base.

### FR-12 Coach wiring (test baselines feed prescriptions)
- FR-12.1 Latest e1RM per lift feeds %1RM working loads in SetTarget / PrescribedSession.
- FR-12.2 VO2max / maxHR feeds cardio zone prescriptions.
- FR-12.3 If a needed baseline is missing, the coach prompts "Run the [X] test to unlock load-based targets" rather than guessing.
- FR-12.4 Coach confidence level (low/moderate/high) reflects data availability.

### FR-13 Built-in programs
- FR-13.1 StrengthPresets catalog includes: 5x5, 5/3/1, PPL, splits, calisthenics, Olympic lifting.
- FR-13.2 All programs reachable from the in-Workout planning surface.
- FR-13.3 Unified exercise browser available for substitutions within programs.
- FR-13.4 Percentage-based programs display computed loads from e1RM when available.
- FR-13.5 Original descriptions; scheme origins attributed; no copyrighted program text.

---

## 6. Non-Functional Requirements

- NFR-1 **Design quality (HIG):** native components, large titles, grouped-inset lists, SF Symbols, system materials/vibrancy, Dynamic Type, light/dark/tinted appearances, restrained motion. Apple Design Award criteria: inclusivity, delight, innovation, visual/graphic craft.
- NFR-2 **Accessibility:** full VoiceOver labels, Dynamic Type to AX5, sufficient contrast, Reduce Motion honored, large tap targets (>=44pt).
- NFR-3 **Privacy (strengthened):**
  - NFR-3.1 **No-network core:** all features work offline / airplane mode. Network is used only to fetch the public exercise-image dataset (cached on device).
  - NFR-3.2 **No third-party SDKs or telemetry.** Zero analytics, zero crash reporters, zero ad frameworks.
  - NFR-3.3 **App Store privacy label: "Data Not Collected."** No data is collected by the developer or any third party.
  - NFR-3.4 **No developer-operated server.** Data is local-first and may sync through the user's private iCloud; portability is also available via JSON export/import.
  - NFR-3.5 **Clear purpose strings** for every permission (HealthKit, Bluetooth, Location, Motion). Each explains exactly what data is accessed and that it never leaves the device.
  - NFR-3.6 **Plain-English privacy commitment:** Cladiron does not collect, transmit, or sell user data. There is no account, no developer-operated server, and no analytics. Health, Bluetooth, and location data stay on the user's device/private iCloud, only with explicit permission. The user can export or delete all data at any time.
- NFR-4 **Performance:** cold launch < 1.5s; logging a set <= 2 taps; charts render < 100ms.
- NFR-5 **Reliability/offline:** fully functional with no network; workout recording survives backgrounding.
- NFR-6 **Licensing boundary:** Cladiron's application code is GPLv3-or-later with the Cladiron App Store Exception. `free-exercise-db-plusplus`, its exercise database, annotations, and related tooling remain open under that project's license. Brand assets remain protected under `TRADEMARKS.md`. Maintain complete third-party notices and a reproducible build.
- NFR-7 **Battery:** GPS + BLE recording optimized; configurable GPS accuracy.
- NFR-8 **Coach suggests, never proscribes (user agency):** the coach engine and every
  coach UI surface must honor the user's stated schedule targets (strength/cardio days,
  rest days, two-a-days) over its own auto-recovery instincts. Recovery, lighter-day, and
  deferral outputs are *advice attached to* the user's plan (cited, dismissible), never a
  silent replacement of a requested session. Every coach surface leaves an escape hatch —
  pick an alternative, open the full cardio picker, or build a strength session anyway.
  Applies to the CoachDecision engine, the weekly planner (FR-12), and all coach cards.

---

## 7. Use Cases

### UC-1 — Log a strength set with live context
- **Actor:** Developer-Athlete
- **Main flow:** (1) Start session. (2) Tap exercise; app shows last-time and PR. (3) Enter weight & reps (<=2 taps for repeat). (4) Set stored, volume updated, rest timer starts. (5) PR badge if beaten.

### UC-2 — Auto-import an Apple Watch run
- **Main flow:** Open app → HealthKit query → new run appears with distance, pace, HR, route.

### UC-3 — Record an outdoor run with iPhone only
- **Main flow:** Start → Run (Outdoor) → GPS route + timer → save HKWorkout.

### UC-4 — Record cardio with a chest strap
- **Main flow:** Start → choose activity → BLE connects → live HR → save with HR series.

### UC-5 — Pair a Bluetooth HRM
- **Main flow:** Settings → HRM → scan → connect → save as default.

### UC-6 — Glance at daily steps
- **Main flow:** Open app → step ring + goal + 7-day trend.

### UC-7 — Migrate from Gmail draft
- **Main flow:** Settings → Import → parse → preview → merge.

### UC-8 — Review exercise progress
- **Main flow:** Exercise detail → trend chart + PR markers + set history.

### UC-9 — Smart Start a workout
- **Main flow:** Start → ranked best-guess list → tap to launch.

### UC-10 — Run a fitness test
- **Actor:** Developer-Athlete
- **Main flow:** (1) Open Tests tab. (2) Select a test (e.g., Cooper 12-min run). (3) Read the self-contained protocol. (4) Perform the test and enter results (distance, time, HR as needed). (5) App computes the metric on-device (e.g., VO2max) and stores it as a baseline. (6) The "Your Fitness" card updates with the new value and trend.

### UC-11 — Coach prescribes loads from test baselines
- **Actor:** Developer-Athlete
- **Main flow:** (1) Open Workout tab. (2) Coach card shows "Bench Press: 4x6 @ 72.5 kg (85% of your 1RM)." (3) Tap "Why this?" → citation sheet shows the evidence. (4) If baseline is missing: "Run the Bench Press 1RM test to unlock load-based targets."

### UC-12 — Follow a built-in program
- **Actor:** Quantified Beginner
- **Main flow:** (1) Workout tab → Programs & Routines. (2) Browse preset programs (e.g., 5/3/1). (3) Tap a session → view exercises with prescribed loads (from e1RM if available). (4) "Start Workout" loads the session. (5) Substitute exercises via the unified browser.

---

## 8. Data Model (sketch)

- **Exercise**: id, name, category, muscleGroups, isCustom, defaultUnit
- **Session**: id, date, title, templateRef?, notes, healthKitWorkoutUUID?
- **SetEntry**: id, sessionRef, exerciseRef, order, weight, reps, rpe?, isWarmup, note, completedAt
- **CardioWorkout**: id, type, start, end, distance?, routeSamples?, hrSamples[], source, healthKitWorkoutUUID
- **Assessment**: id, date, kind, value, inputWeight?, inputReps?, exerciseName?, protocolName?, notes?, inputDistance?, inputTime?, inputEndingHR?, inputAge?, inputSex?, updatedAt, originDevice
- **HRMDevice**: id, name, lastBattery, isDefault
- **WorkoutPreset**: id, activityType, label, defaultSettings, lastUsedAt, useCount
- **PRSnapshot** (derived): exerciseRef, rule, value, achievedAt
- **Sync metadata:** every entity carries stable UUID + `updatedAt` + `originDevice`

Schema changes are **additive only** — optional fields, no unique constraints, no destructive migrations. The local store + existing JSON exports must stay safe.

## 9. Phasing

- **CadenceCore (foundation):** data model, PR logic, coaching engine, assessment math, export/import layer. Testable with `swift test`. Prerequisite to everything.
- **v1 — iPhone-only (current release):**
  - P1: Docs/repositioning (naming, requirements consolidation, privacy NFRs)
  - P2: Information architecture (Workout/Tests/Progress tabs, Library relocation, exercise browser unification)
  - P3: Tests engine (on-device VO2max, no-lab battery, fitness baseline card)
  - P4: Coach wiring (test baselines feed recommendations, citations UI)
  - P5: Built-in programs (5/3/1, PPL + planning surface integration)
- **v2 — watch-first:** FR-8 (wrist logging + live cardio) — **shipped early, 2026-07-17**; FR-7 (Smart Start) remains.
- **v3 — sensors & enhancements:** FR-7 enhancements (FTMS/NFC/beacon), advanced assessments.

## 10. Resolved Decisions

- PR default: estimated 1RM (Brzycki formula). Configurable.
- Units: kg canonical, lb toggle global.
- Portability: complete JSON export/import plus private-iCloud mirroring. WatchConnectivity supports live handoff and durable workout completion delivery.
- Watch store: local store (no sync).
- IA: Workout / Tests / Progress (3 tabs). Planning inside Workout.
- Naming: Cladiron (user-visible), Cadence (internal codename).
- Wingate: kept but gated behind "advanced" (no-lab constraint).

## 11. Open Questions

- Cardio coaching scope for v2 (HR zone training plans? Running programs?).
- Watch weight entry UX (Digital Crown increments vs quick-pick chips).
- Assessment retest cadence (fixed 30 days vs adaptive based on training load).
