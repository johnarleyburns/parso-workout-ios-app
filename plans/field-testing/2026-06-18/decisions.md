# Decisions — 2026-06-18 Cladiron IA + Tests + Coach Wiring

All binding. Do not re-litigate without asking.

## Locked (from user)

| # | Decision |
|---|----------|
| L1 | Tab bar = Workout / Tests / Progress (3 tabs). |
| L2 | Planning (program selection + routine building) lives INSIDE the Workout tab, not its own tab. |
| L3 | Drop Wingate from the default test battery. Keep enum case; gate behind "advanced — requires ergometer." |
| L4 | "Cladiron" is the product name shown to users at all times. "Cadence" is internal codename only — repo, Xcode project, scheme, Swift package, bundle ID, type names stay as-is. |

## Information Architecture (P2)

| # | Decision |
|---|----------|
| IA1 | Workout tab (Home) retains hero → strength, secondary cardio. Title displays "Cladiron." |
| IA2 | Planning entry (Programs / Routines) added to Workout tab — button/section that opens the relocated routine surface from Library. |
| IA3 | Tests tab replaces Plan tab. Shows assessment battery + "Your fitness" baseline header. `accessibilityIdentifier("tab.tests")`. |
| IA4 | Progress tab replaces Library tab. Promotes HistoryView + test-result trends. `accessibilityIdentifier("tab.progress")`. |
| IA5 | Library tab removed. Its Routines segment → planning surface in Workout. Its Exercises browser → unified with ExercisePickerView. |
| IA6 | Unified exercise browser keeps LibraryView's richer affordances (body-part chips, popular-first, muscle subtitles, detail view). Presented from (a) in-session add-exercise and (b) planning/routine surface. |
| IA7 | Additive-before-subtractive: stand up new structure, verify green, then remove old tabs/views. |

## Tests Engine (P3)

| # | Decision |
|---|----------|
| T1 | Hard constraint: tests require only an ordinary gym + field/track + app stopwatch + optionally BLE chest strap (0x180D). No lab gear. |
| T2 | Cardio tests compute VO2max ON-DEVICE (no "use online calculators" punt). |
| T3 | Cardio test protocols: Cooper 12-min, 1.5-mile run, Rockport 1-mile walk, optionally Queens College step test. |
| T4 | Each protocol uses published equations with cited constants (Cooper 1968, Kline/Rockport 1987, etc.) registered in CitationRegistry. |
| T5 | Wingate kept as AssessmentKind case but hidden from default battery. Gated behind "advanced — requires ergometer" affordance. |
| T6 | "Your fitness" baseline card shows: estimated 1RMs (main lifts), VO2max + fitness category, endurance benchmarks, run times, with AssessmentTrend pills and "last tested / re-test due" nudge. |
| T7 | Fitness baseline also surfaces in Progress tab as test trends. |

## Coach Wiring (P4)

| # | Decision |
|---|----------|
| C1 | Latest test baselines feed into RecommendationEngine via TrainingFacts: e1RM per lift → %1RM working loads; VO2max/maxHR → cardio zones. |
| C2 | If a needed baseline is missing, the coach prompts "Run the [X] test to unlock load-based targets" rather than guessing. |
| C3 | "Why this?" affordance on CoachCardView prescriptions opens cited source(s) from CitationRegistry. |
| C4 | Each Test also links its cited source via CitationRegistry. |

## Built-in Programs (P5)

| # | Decision |
|---|----------|
| BP1 | Audit StrengthPresets; add missing widely-known schemes: 5/3/1, GZCLP, nSuns, PPL. |
| BP2 | All programs reachable from the in-Workout planning surface with unified exercise browser for substitutions. |
| BP3 | Write original descriptions for each scheme (no copyrighted program text). Attribute scheme origins. |

## Docs / Repositioning (P1)

| # | Decision |
|---|----------|
| D1 | Reconcile root REQUIREMENTS.md (v0.3) + docs/REQUIREMENTS.md (v0.2) → single canonical docs/REQUIREMENTS.md. Root becomes stub redirect. |
| D2 | Vision repositioned: free, open-source, privacy-first, iPhone-native strength COACH; cardio secondary/capture-only; auditable science; field-testable fitness; built-in established programs. |
| D3 | Privacy NFRs strengthened: no-network core, no third-party SDKs/telemetry, airplane-mode capable, App Store privacy label "Data Not Collected," sync only user's iCloud. |
| D4 | IA section rewritten to Workout / Tests / Progress. FRs added for Tests battery + in-app citations. Phasing updated. |
| D5 | CLAUDE.md updated: "What this is" + IA section reflects new structure. |
| D6 | Grep app for user-visible "Cadence" strings and switch to "Cladiron" — WITHOUT touching type names, scheme, package, or bundle ID. |
