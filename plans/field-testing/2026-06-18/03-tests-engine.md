# P3 — Tests Engine (No-Lab Battery Feeds the Coach)

**Branch:** `p3/tests-engine` (stacks on P2)
**Risk:** Low (pure logic + new views, additive schema)
**Depends on:** P2 (Tests tab must exist)

---

## Problem

The Assessment domain exists but cardio tests punt to "online calculators and wearable
devices" (`vo2maxField.protocolText`). The app should compute VO2max on-device from
standard field-test protocols, using published equations with cited constants. Wingate
requires a cycle ergometer (violates no-lab constraint). The "Your fitness" baseline card
is a shell.

## What the Code Does Today

### Assessment.swift (198 lines)
- `AssessmentKind`: 9 cases — `e1RM`, `repMax`, `pushupMax`, `pullupMax`,
  `bodyweightSquatMax`, `plankHold`, `hollowHold`, `vo2maxField`, `wingate`.
- `AssessmentCategory`: `strength`, `strengthEndurance`, `cardio`.
- `AssessmentUnit`: `weightKg`, `reps`, `seconds`, `mlKgMin`, `watts`.
- `vo2maxField.protocolText`: "VO2max field estimate — see online calculators and
  wearable devices."

### AssessmentMath.swift (139 lines)
- `e1RM(weight:reps:)` — Brzycki formula.
- `minimalDetectableChange(baselineSD:)` — MDC guardrail.
- `isRetestDue(lastDate:)` — 30-day default.
- `summaries(from:)` — longitudinal snapshot.

### CardioMath.swift (88 lines)
- `hrZone()`, `defaultMaxHR()`, `paceSecPerKm()`, `estimateCalories()`.
- No VO2max estimation functions.

### Citation.swift (120 lines)
- `CitationRegistry` has `cooperVo2max` (Cooper 1968), `wingateTest`. Missing: 1.5-mile,
  Rockport, Queens College.

### RecordAssessmentView.swift (in Features/Plan/)
- Input form for recording assessments. Needs extension for cardio-specific inputs
  (distance, time, ending HR).

## Design

### 1. Cardio Test Protocols — On-Device Computation

Add to `CardioMath.swift` (or a new `VO2maxEstimation.swift` in CadenceCore):

**Cooper 12-Minute Run:**
```
VO2max = (distance_m - 504.9) / 44.73
```
Input: distance in meters. Citation: Cooper 1968.

**1.5-Mile (2.4 km) Run:**
```
VO2max = 483 / time_minutes + 3.5
```
(Using the standard published regression.) Input: run time. Citation: encode the standard
ACSM/military reference.

**Rockport 1-Mile Walk:**
```
VO2max = 132.853 - (0.1692 * weight_kg * 2.2046)
         - (0.3877 * age)
         + (6.315 * sex_code)    // 1=male, 0=female
         - (3.2649 * walk_time_min)
         - (0.1565 * ending_HR_bpm)
```
Input: age, sex, weight (kg), walk time (minutes), ending HR (from chest strap or manual).
Citation: Kline et al. 1987.

**Queens College 3-Minute Step Test (optional):**
```
Men:   VO2max = 111.33 - (0.42 * recovery_HR)
Women: VO2max = 65.81 - (0.1847 * recovery_HR)
```
Input: recovery HR (15-sec count * 4, taken 5-20 sec post-exercise). Citation: McArdle
et al. 1972.

### 2. AssessmentKind Extensions

Add new `AssessmentKind` cases for each cardio protocol:
```swift
case cooper12min      // category: .cardio, unit: .mlKgMin
case run1_5mile       // category: .cardio, unit: .mlKgMin
case rockportWalk     // category: .cardio, unit: .mlKgMin
case queensCollegeStep // category: .cardio, unit: .mlKgMin (optional)
```

Or: extend the existing `vo2maxField` with a `protocolName` discriminator. **Decision
needed:** new enum cases vs. protocol-name-on-existing-case. Recommendation: **new enum
cases** for type safety and independent `protocolText`.

Keep `vo2maxField` as a legacy/generic case (manual entry from a wearable). The new cases
are the on-device computed ones.

### 3. Assessment Model — Additive Schema Changes

Add optional fields to `Assessment` (additive, defaulted):
```swift
@Attribute var inputDistance: Double?   // meters (Cooper, 1.5-mile)
@Attribute var inputTime: Double?       // seconds (all run/walk tests)
@Attribute var inputEndingHR: Double?   // bpm (Rockport, Queens College)
@Attribute var inputAge: Int?           // years (Rockport)
@Attribute var inputSex: Int?           // 0=female, 1=male (Rockport)
```

These are optional with no default → existing data unaffected. CloudKit safe.

### 4. Wingate Gating

- Keep `AssessmentKind.wingate` enum case.
- In the Tests tab battery list, hide Wingate from the default view.
- Add an "Advanced Tests" expandable section with a note: "Requires a cycle ergometer."
- `wingate.protocolText` remains unchanged.

### 5. "Your Fitness" Baseline Card (Real Content)

In `TestsView` (P2), replace the shell header with a real `FitnessBaselineCard`:

```
┌─────────────────────────────────────────┐
│  YOUR FITNESS BASELINE                  │
├─────────────────────────────────────────┤
│  STRENGTH                               │
│  Bench Press  e1RM: 100 kg  ▲ +5%      │
│  Squat        e1RM: 140 kg  ▲ +3%      │
│  Deadlift     e1RM: 180 kg  → 0%       │
│  last tested 12 days ago                │
│                                         │
│  CARDIO                                 │
│  VO2max: 42.3 ml/kg/min  (Good)  ▲ +2% │
│  Cooper: 2,450 m    last tested 28d    │
│  1.5-mi: 11:30      ⚠ re-test due     │
│                                         │
│  ENDURANCE                              │
│  Push-ups: 45   ▲ +12%                 │
│  Pull-ups: 12   → 0%                   │
│  Plank: 2:15    ▲ +8%                  │
│                                         │
│  [Re-test overdue: 1.5-mile run]       │
└─────────────────────────────────────────┘
```

Each row: latest value + AssessmentTrend pill + "last tested / re-test due" nudge.
VO2max gets a conservative fitness-category label (Excellent/Good/Fair/Below Average/Poor)
based on age+sex normative tables (ACSM).

### 6. Test Trends in Progress Tab

Surface a "Test History" section in ProgressView (P2) showing:
- Sparkline or mini-chart per test kind (using Swift Charts)
- Latest value + trend arrow
- Tap → full AssessmentDetailView

### 7. CitationRegistry Additions

Add to `Citation.swift`:
```swift
static let run1_5mile = Citation(...)     // ACSM reference
static let rockportWalk = Citation(...)   // Kline et al. 1987
static let queensCollegeStep = Citation(...) // McArdle et al. 1972
```
`cooperVo2max` already exists.

### 8. RecordAssessmentView Extensions

Per-kind cardio input forms:
- **Cooper:** distance input (meters or miles, auto-convert)
- **1.5-mile:** time input (mm:ss picker)
- **Rockport:** time input + ending HR + age + sex (age/sex from HealthKit if available)
- **Queens College:** recovery HR + sex
- **Generic vo2maxField:** manual VO2max number (from wearable)

Each form shows `protocolText` as inline instructions (self-contained — the app gives the
number, no external calculator needed).

## Implementation Steps

1. Add VO2max estimation functions to `CadenceCore/CardioMath.swift` with `swift test` coverage
2. Add new `AssessmentKind` cases (cooper12min, run1_5mile, rockportWalk, queensCollegeStep)
3. Add optional input fields to `Assessment` model (additive schema)
4. Add citations to `CitationRegistry`
5. Write `protocolText` for each new kind (self-contained instructions)
6. Gate Wingate behind "Advanced — requires ergometer" in TestsView
7. Build `FitnessBaselineCard` view with real content
8. Add VO2max fitness-category classification (ACSM normative tables) to AssessmentMath
9. Extend `RecordAssessmentView` with per-kind cardio input forms
10. Add test trends section to ProgressView
11. Wire citations to each test's detail view
12. Add new files to pbxproj
13. `cd CadenceCore && swift test` (new math tests must pass)
14. `xcodebuild build`
15. Accessibility: VoiceOver + Dynamic Type on all new/changed views

## Testing

- **Unit tests (CadenceCore):** VO2max estimation functions against known reference values.
  - Cooper: 2400m → ~42.4 ml/kg/min
  - 1.5-mile: 12:00 → ~43.8 ml/kg/min
  - Rockport: known inputs → expected output from Kline 1987
  - Queens College: recovery HR 140 male → ~52.5 ml/kg/min
  - Edge cases: zero distance, very fast/slow times, boundary HR values
- **Unit tests:** fitness-category classification against ACSM tables
- **Unit tests:** Wingate still exists as an AssessmentKind but hidden from default battery
- `xcodebuild build`
- UI tests: record a Cooper test → verify VO2max computed and displayed
- Accessibility audit on all new views
