# Cadence — Requirements & Use Cases

> Working title: **Cadence** (rename freely). An open-source, privacy-first iOS app that unifies strength training, cardio (with or without an Apple Watch), and daily steps in one place — built to Apple HIG standards.

**Status:** Draft v0.3 · **Platforms:** **v1 ships iPhone-only (iOS 17+).** watchOS 10+ is planned but **deferred** (hardware); in v1, Watch-recorded workouts/steps/HR are read from HealthKit. · **License:** MIT (proposed) · **Distribution:** Source + TestFlight

> **v1 release scope:** log strength on the phone; read steps + ingest Watch-recorded workouts/HR from HealthKit; review history, PRs, and trends. The watch app (FR-8) and on-device cardio/sensors move to later releases — see §8.

---

## 1. Vision & Goals

Cadence exists to close a specific gap: there is no free app that logs **detailed strength workouts** (per-set weight/reps with PR and last-time recall), ingests **Apple Watch cardio with heart rate**, supports **watchless cardio with a chest strap for accuracy**, and keeps **daily steps front and center** — all in one privacy-respecting, beautifully designed app.

**Primary goals**

- One home for strength, cardio, and steps with no subscription and no data leaving the device by default.
- Strength logging that is *faster than a Gmail draft*, with instant PR and last-time context while lifting.
- Accurate watchless cardio via Bluetooth chest strap, plus automatic ingest of Watch workouts when worn.
- **Watch-first workouts:** log sets and run cardio entirely from the wrist (Digital Crown), with the watch working even when the phone is absent. The **iPhone is the review/progress hub** and the fallback logger for watchless days.
- An interface refined enough to be Apple Design Award–worthy: fluent, legible, fully accessible, alive with restrained motion.

**Non-goals (for v1)**

- Social feeds, coaching marketplaces, or AI form-checking.
- Android or web clients.
- Nutrition/macro tracking (may sync bodyweight only).
- Cloud accounts or server-side storage.

## 2. Personas

- **The Developer-Athlete (primary):** trains with weights 3–5×/week, runs/cycles/boxes/swims, cares about PRs and trends, sometimes leaves the watch at home. Wants data ownership and a clean tool.
- **The Quantified Beginner (secondary):** wants steps + simple workout logging without paying or being upsold.

## 3. Glossary

- **Set:** one bout of an exercise — a weight × reps pair (optionally RPE/notes).
- **PR:** personal record for an exercise (heaviest weight, best estimated 1RM, or best volume).
- **Last-time:** the most recent prior performance of the same exercise, shown inline while logging.
- **Session:** a dated collection of exercises and their sets (a "workout").
- **HRM:** Bluetooth LE heart-rate monitor (chest strap or armband) exposing the standard Heart Rate Service (0x180D).

---

## 4. Functional Requirements

### FR-1 Strength logging
- FR-1.1 Create a session and add exercises from a searchable library (with custom exercises and categories: push/pull/legs, or muscle group).
- FR-1.2 Log multiple sets per exercise; each set captures weight, reps, optional RPE and note. Different weights may have different rep counts within one exercise.
- FR-1.3 While logging a set, display the matching **last-time** set and the current **PR** for that exercise inline.
- FR-1.4 Auto-detect and flag a new PR (configurable: 1RM estimate, top weight, or top volume).
- FR-1.5 Rest timer between sets, auto-startable on set completion.
- FR-1.6 Reusable session templates (e.g., "Push Day").
- FR-1.7 Edit/delete past sets and sessions.

### FR-2 Cardio tracking
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
- FR-4.1 Request least-privilege HealthKit read/write authorization with clear in-context priming before the system sheet.
- FR-4.2 Local-first storage (SwiftData/Core Data) as the source of truth for the rich strength model HealthKit cannot represent (exercise → sets → reps → weight).
- FR-4.3 Write summary strength workouts to HealthKit (duration, energy, `.traditionalStrengthTraining`) for unified history; keep detailed set data local.
- FR-4.4 **Chest strap:** discover, connect, and subscribe to a BLE HRM via the standard Heart Rate Service (0x180D / characteristic 0x2A37); reconnect automatically; surface battery and signal status; persist a remembered device.
- FR-4.5 Optional iCloud/CloudKit private-database sync across the user's own devices (off by default).

### FR-5 History, PRs & trends
- FR-5.1 Per-exercise history list and trend chart (top weight, est. 1RM, volume over time).
- FR-5.2 PR timeline per exercise and a global "recent PRs" view.
- FR-5.3 Cardio history with HR overlay, pace splits, and route map.
- FR-5.4 Calendar/heatmap of training consistency.

### FR-6 Migration & export
- FR-6.1 One-time importer that parses the existing Gmail-draft format (category, exercise, weight, sets×reps, PR, last-time) into the local store.
- FR-6.2 Full data export (JSON/CSV) and import — the user owns and can leave with their data.

### FR-7 Smart Start (best-guess preselect, graceful degradation)
**Core principle:** the ranked best-guess list is the baseline experience and must work with **zero** special hardware — no Bluetooth, FTMS, NFC, beacons, or UWB. Those are strictly additive: they *confirm, skip, or enrich* the list, and their absence never degrades it.

- FR-7.1 On Start (or app open), present a ranked **best-guess list** of likely workouts; one tap launches the top guess preconfigured. "Browse all" is always one tap away.
- FR-7.2 Ranking uses only always-available signals, each optional and individually removable:
  - **History & habit** (always works, even offline): recency and frequency of the user's own sessions.
  - **Time context:** time-of-day and weekday patterns (e.g., "Tue 6pm → treadmill intervals").
  - **Location** (if permitted): geofence tells which gym/home, biasing the list; if denied, ranking falls back to history + clock.
  - **Motion** (if permitted): `CMMotionActivity` disambiguates running vs cycling vs stationary.
  - **Heart rate** (if a watch/strap is connected): intensity context only — never required.
- FR-7.3 The top guess is highlighted but **never auto-committed** without confirmation, unless the user explicitly opts into auto-start.
- FR-7.4 **Progressive enhancement (all optional):** a detected FTMS/CSC/RSC machine auto-selects that type and ingests live metrics; an NFC tap loads an exact preset and skips the list; a known beacon/UWB tag refines the guess. Any of these may be missing with no loss of baseline function.
- FR-7.5 **Learning:** each confirmed selection feeds back to improve future ranking (per-location, per-time).
- FR-7.6 Manual override is always present and remembered as a signal.
- FR-7.7 **Cold start:** with no history, fall back to sensible category defaults (Run / Bike / Strength / Other) rather than an empty list.

### FR-8 Apple Watch (watch-first workouts)
- FR-8.1 **Standalone** watchOS app that runs an entire workout with no phone present.
- FR-8.2 **Wrist strength logging:** pick exercise, dial weight/reps with the **Digital Crown**, tap to log a set; last-time and PR shown inline; rest timer with haptics; swipe between exercises.
- FR-8.3 **Live cardio on watch** via `HKWorkoutSession` + `HKLiveWorkoutBuilder`: real-time HR, zones, calories, duration; start/pause/end from the wrist.
- FR-8.4 **Smart Start on the wrist:** the same ranked best-guess list (FR-7), condensed for the watch.
- FR-8.5 Distinct **haptic cues** for set logged, new PR, rest complete, and HR-zone change.
- FR-8.6 **Complication / Smart Stack** entry to start a workout in one tap.
- FR-8.7 If the phone is unreachable, log locally on the watch and reconcile later (see FR-9).

### FR-9 Cross-device sync & roles
- FR-9.1 Each device keeps a **local store**; both are clients of the user's **private CloudKit database** (recommended) so either works offline and reconciles automatically. WatchConnectivity is used for live handoff/quick transfer, **not** as the system of record.
- FR-9.2 Every entity carries a **stable UUID** + `updatedAt`; conflict resolution is last-write-wins at the set/field level; no duplicate sessions across devices.
- FR-9.3 **Role split:** the watch is the in-workout surface; the **phone is the analysis surface** (trends, PRs, history, import/export) and the watchless fallback logger.
- FR-9.4 Sync stays in the user's own iCloud and can be disabled to run fully local on a single device.

---

## 5. Non-Functional Requirements

- NFR-1 **Design quality (HIG):** native components, large titles, grouped-inset lists, SF Symbols, system materials/vibrancy, Dynamic Type, light/dark/tinted appearances, and tasteful, purposeful motion. Target Apple Design Award criteria: inclusivity, delight, innovation, visual/graphic craft.
- NFR-2 **Accessibility:** full VoiceOver labels, Dynamic Type to AX5, sufficient contrast, Reduce Motion honored, large tap targets (≥44pt).
- NFR-3 **Privacy:** on-device by default; no analytics SDKs; HealthKit data never leaves the device unless the user enables iCloud sync; clear purpose strings.
- NFR-4 **Performance:** cold launch < 1.5s; logging a set < 2 taps; charts render < 100ms on recent devices.
- NFR-5 **Reliability/offline:** fully functional with no network; workout recording survives backgrounding and interruptions.
- NFR-6 **Open source:** MIT-licensed, documented build, no proprietary dependencies; reproducible from a clean checkout in Xcode.
- NFR-7 **Battery:** GPS + BLE recording optimized to avoid excessive drain; configurable GPS accuracy.

---

## 6. Use Cases

Each use case lists Actor, Preconditions, Main flow, and Alternates.

### UC-1 — Log a strength set with live context
- **Actor:** Developer-Athlete
- **Preconditions:** App installed; exercise exists in library.
- **Main flow:** (1) Start/resume today's session. (2) Tap an exercise; app shows last-time sets and current PR. (3) Enter weight & reps, tap Add Set (≤2 taps for a repeat). (4) App stores the set, updates running volume, and triggers rest timer. (5) If the set beats the PR rule, a PR badge animates in.
- **Alternates:** (3a) Same as last set → one-tap "repeat". (2a) Exercise not in library → create custom exercise inline.

### UC-2 — Auto-import an Apple Watch run
- **Actor:** Developer-Athlete (wearing watch)
- **Preconditions:** HealthKit read authorized; Watch saved a workout.
- **Main flow:** (1) Open app. (2) App queries HealthKit for new workouts since last sync. (3) New run appears in history with distance, pace, HR curve, and route — no manual entry.
- **Alternates:** (2a) No new workouts → nothing added. (2b) Duplicate already imported → skipped by UUID.

### UC-3 — Record an outdoor run with iPhone only (no watch)
- **Actor:** Quantified Beginner
- **Preconditions:** Location permission granted.
- **Main flow:** (1) Tap Start → Run (Outdoor). (2) App starts GPS route + timer, shows live pace/distance/duration. (3) User finishes; app saves an `HKWorkout` with route and metrics back to HealthKit.
- **Alternates:** (2a) GPS weak → app warns and continues with reduced accuracy. (2b) Phone call interrupts → recording continues in background.

### UC-4 — Record cardio with a chest strap for accurate HR (no watch)
- **Actor:** Developer-Athlete
- **Preconditions:** BLE on; chest strap powered.
- **Main flow:** (1) Tap Start → choose activity (e.g., Boxing). (2) App connects to the saved strap (or scans for a new one). (3) Live HR and HR zone display in real time; user trains. (4) On finish, app saves the workout with the captured HR series to HealthKit.
- **Alternates:** (2a) No saved strap → open pairing screen (UC-5). (3a) Signal drops → app shows "reconnecting", buffers, and resumes. (4a) Strap battery critical → warn before/after.

### UC-5 — Pair a Bluetooth heart-rate monitor
- **Actor:** Developer-Athlete
- **Preconditions:** BLE permission granted; strap in pairing range.
- **Main flow:** (1) Open Settings → Heart-Rate Monitor → Add Device. (2) App scans for devices advertising Heart Rate Service (0x180D). (3) User taps a device; app connects, shows live BPM and battery, and saves it as the default.
- **Alternates:** (2a) None found → guidance (wet electrodes, wake strap, check battery). (3a) Connect fails → retry/forget options.

### UC-6 — Glance at daily steps & activity
- **Actor:** Any user
- **Preconditions:** HealthKit step read authorized.
- **Main flow:** (1) Open app to Today. (2) Step ring shows progress toward goal with current count, plus distance, flights, and active energy. (3) Tap to see a 7-day trend and history.
- **Alternates:** (1a) No authorization → contextual prompt explaining why steps are needed.

### UC-7 — Migrate history from the Gmail draft
- **Actor:** Developer-Athlete
- **Preconditions:** Draft text available (paste or file).
- **Main flow:** (1) Settings → Import → Paste/Upload. (2) App parses categories, exercises, weights, sets×reps, PR and last-time markers. (3) Preview shows parsed sessions; user confirms. (4) Data merges into the local store; PRs recomputed.
- **Alternates:** (2a) Unparseable lines → flagged for manual edit, rest imported.

### UC-8 — Review an exercise's progress
- **Actor:** Developer-Athlete
- **Main flow:** (1) Open exercise detail. (2) See trend chart (top weight / est. 1RM / volume) with PR markers and the full set history. (3) Switch metric or time range.

### UC-9 — Smart Start a cardio session (no hardware required)
- **Actor:** Any user
- **Preconditions:** None hard-required. Works with no permissions and no history (cold-start defaults).
- **Main flow:** (1) Tap Start (or open app). (2) App shows a ranked best-guess list — e.g., *Treadmill · Intervals* on top, then *Outdoor Run* and *Spin Bike*, then "Browse all". (3) User taps the right one; the workout opens preconfigured. (4) The choice is remembered to improve future ranking.
- **Alternates:**
  - **(a) No history (cold start):** list shows category defaults (Run / Bike / Strength / Other).
  - **(b) Location denied:** ranking falls back to time-of-day + habit; everything still works.
  - **(c) Motion available:** running vs cycling is disambiguated automatically, reordering the list.
  - **(d) FTMS machine in range (enhancement):** that machine is auto-highlighted with a "connected" badge and live metrics; user can still pick anything else.
  - **(e) NFC tag tapped (enhancement):** the tag's exact preset loads immediately, skipping the list.
  - **(f) Known beacon/UWB tag (enhancement):** nudges the top guess; absence is a no-op.

### UC-10 — Log a strength set from the wrist
- **Actor:** Developer-Athlete (watch on, mid-set)
- **Preconditions:** Session started (on watch or phone).
- **Main flow:** (1) Glance at the watch: current exercise, *Set N of M*, last-time and PR shown. (2) Rotate the Digital Crown to adjust reps/weight. (3) Tap **Log Set** → haptic confirms, rest timer starts; a beaten PR fires a distinct haptic + badge. (4) Swipe to the next exercise.
- **Alternates:** (2a) Matches plan → tap logs immediately, no dialing. (3a) Phone absent → stored locally, synced when reunited.

### UC-11 — Train with the watch only, phone left behind
- **Actor:** Developer-Athlete (phone in the locker)
- **Preconditions:** Watch app installed; local store on the watch.
- **Main flow:** (1) Start a workout from the complication or wrist Smart Start. (2) Log every set / record cardio with HR entirely on the wrist. (3) Finish → watch saves locally and to HealthKit. (4) Back near the phone (or via iCloud), data reconciles; the session appears in phone history and trends.
- **Alternates:** (4a) Conflicting edits → resolved per FR-9.2. (1a) Using a chest strap → it pairs to the *watch* over BLE for HR.

---

## 7. Data Model (sketch)

- **Exercise**: id, name, category, muscleGroups, isCustom, defaultUnit
- **Session**: id, date, title, templateRef?, notes, healthKitWorkoutUUID?
- **SetEntry**: id, sessionRef, exerciseRef, order, weight, reps, rpe?, isWarmup, note, completedAt
- **CardioWorkout**: id, type, start, end, distance?, routeSamples?, hrSamples[], source(watch|iphone|strap|machine), healthKitWorkoutUUID
- **HRMDevice**: id (CB peripheral UUID), name, lastBattery, isDefault
- **WorkoutPreset**: id, activityType, label (e.g., "Treadmill — Intervals"), defaultSettings, lastUsedAt, useCount — *optional links:* nfcTagId?, ftmsServiceUUID?, beaconId?
- **SmartStartContext** (derived, not persisted): gymId?, motionClass?, timeBucket, recencyScore, currentHR? → produces the ranked preset list
- **PRSnapshot** (derived/cached): exerciseRef, rule, value, achievedAt
- **Sync metadata:** every persisted entity carries a stable `id` (UUID), `updatedAt`, and `originDevice` for CloudKit reconciliation across watch + phone

The hardware hooks (`nfcTagId`, `ftmsServiceUUID`, `beaconId`) are **nullable by design** — a preset is fully usable without any of them.

The model lives in a **shared Swift package** consumed by both the watchOS and iOS targets, so logging logic is written once. CloudKit private-DB sync keeps both stores eventually consistent; the watch can log standalone and reconcile later.

HealthKit holds: steps, summary `HKWorkout`s, HR series, routes, bodyweight. Rich set/rep/weight detail stays in the local store (HealthKit has no native schema for it).

## 8. Phasing (maps to effort)

- **Shared core (foundation):** the `CadenceCore` Swift package — data model, PR logic, Smart Start ranking, sync layer — testable with `swift test`. Prerequisite to everything. ✅ scaffolded.
- **v1 — iPhone-only (current release):** FR-1 (strength logging **on the phone**), FR-3 (steps from HealthKit), FR-2.1 (ingest Watch-recorded workouts + HR from HealthKit), FR-4.1/4.2/4.3, FR-5 (history/PRs/trends), FR-6 (Gmail import, optional), FR-9 (CloudKit backup, optional/non-blocking). UC-1/2/6/7/8.
- **v2 — watch-first (when hardware allows):** FR-8 (wrist logging + live cardio), FR-7 (Smart Start), UC-9/10/11.
- **v3 — on-device cardio & sensors:** FR-2.2–2.5 (iPhone GPS cardio, **chest-strap HR**), FR-4.4, FR-7 enhancements (FTMS/NFC/beacon), UC-3/4/5. *(Chest strap is a strong candidate to pull into v2 — it gives accurate HR without the watch.)*

## 9. Open Questions

- PR definition default — heaviest weight, estimated 1RM, or best volume?
- Units — lb/kg toggle global or per-exercise?
- Which estimated-1RM formula (Epley vs Brzycki)?
- Sync model — CloudKit private DB (recommended; works offline + standalone watch) vs WatchConnectivity-only?
- Does the watch hold a **full** local store, or a lightweight session buffer that syncs to the phone as system-of-record?
- Watch weight entry — fine Digital-Crown increments, or quick-pick chips for common jumps (+2.5 / +5 kg)?
