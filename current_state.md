# Current State — Cadence field-testing redesign

Live handoff/progress tracker.

_Last updated: 2026-06-25 — User-configurable schedule preferences replacing hard-coded weekly planning._

## What just shipped — Schedule preferences
- **CoachSchedulePreferences** (`CadenceCore/CoachSchedulePreferences.swift`): `Weekday` (calendar-safe), `RestPreference` (.fixed/.rolling), `SameDayCardioTiming`, `CoachSchedulePreferences` with constrained setters (strengthDays 2–5, cardioDays 0–7).
- **Persistence in AppSettings** as JSON in UserDefaults (`settings.coachSchedulePreferences`), defaulting to strength=2, cardio=3, rolling rest every 3 days, two-a-days off.
- **Onboarding schedule page** (step 3 of 6): segmented pickers for strength (2–5) and cardio (0–6) days.
- **CoachDecisionEngine.run** now accepts `schedulePreferences`, threading through scoring, observed facts, and tomorrow preview. Dynamic strength target in observed facts.
- **WeeklyBalance** gains `cardioDays` (distinct aerobic-event days this calendar week).
- **WeeklyPlan redesigned**: days contain `[PlannedSession]` (max one strength, one cardio); two-a-days gated by `allowsTwoADays`; cardio timing notes ("after lifting" / "later in the day"); horizon extended to current-week remainder + full next week. Added `nextWeekDays`, `plannedCurrentWeekSessions`, `plannedNextWeekSessions`.
- **YourWeekView**: fixed Sunday bug (now uses `DateFormatter` instead of manual index math), removed 7-day history section, added "Planned (next week)", renders multi-session chips, dynamic targets.
- **WhyThisTodayView**: "My Preferences" section with controls for all preferences, citation links (strength frequency, aerobic health floor, recovery monitoring, concurrent training).
- **SplashView**: greyscale-only background (`systemGray6`), centered "Cladiron / Your strength coach" text only; removed logo/icon/dumbbell/SFSymbol fallback.
- **AboutView**: removed splash image attribution block.
- **Citations**: added `cdcActivityGuidelines2018` (CDC/HHS guideline) and `murlasitsConcurrentSequence2018` (concurrent-training sequence meta-analysis). New `schedulePreference` and `publicHealthGuideline` evidence categories with dedicated pools. Existing `frequencyMeta`, `pellandDoseResponse2026`, `schumannConcurrent2022`, `sawMonitoring2016`, `halsonRecovery2014` reused in schedule pool.
- **Tests**: 13 new `CoachSchedulePreferencesTests` (defaults, clamping, Codable round-trips, strength targets 2/3/5, cardio-day independence, two-a-day gating, timing notes, fixed/rolling rest, dynamic observed facts). Updated 2 existing WeeklyPlan tests. All CadenceCore tests pass; iOS build green.
- **CLAUDE.md**: post-task checklist now marked MANDATORY with explicit commit/merge/push requirement.

## Repo / branch
- Repo: `/Users/arley/github/parso-workout-ios-app`
- **`main`** = current. Builds + tests green.
- Commit: `c31d475` — pushed, CI in progress.

## Notes / decisions in effect
- All merges to `main` so far were fast-forward; PRs #7–#13.
- Schema changes additive + CloudKit-safe; `[String]` model attrs are delimited-String-backed (`StringArray`).
- `CoachPreferenceProfile` stored as JSON `Data` in UserDefaults under key `settings.coachPreferenceProfile` (not SwiftData).
- `CoachSchedulePreferences` stored as JSON `Data` in UserDefaults under key `settings.coachSchedulePreferences` (same pattern).
