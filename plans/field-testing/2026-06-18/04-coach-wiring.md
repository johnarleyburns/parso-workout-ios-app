# P4 — Coach Wiring (Close the Loop)

**Branch:** `p4/coach-wiring` (stacks on P3)
**Risk:** Low (wiring existing pieces)
**Depends on:** P3 (test baselines must exist)

---

## Problem

The recommendation engine (RecommendationEngine + Recommendation + TrainingFacts) and the
test baselines (Assessment + AssessmentMath) exist as independent systems. The coach
doesn't use test results to prescribe loads or cardio zones. Citations exist in
CitationRegistry but aren't surfaced in the UI.

## What the Code Does Today

### Recommendation.swift (208 lines)
- `SetTarget`: concrete prescription with `sets`, `repsLow/High`, `loadKg`, `rir`.
- `PrescribedSession`: loggable session blueprint with `loadKg`.
- `Recommendation`: full struct with `citation` field (String).

### TrainingFacts.swift (in CadenceCore)
Aggregates training history for the recommendation engine. Currently does NOT include
assessment baselines.

### RecommendationEngine.swift / RecommendationRule.swift (in CadenceCore)
Generates recommendations. Currently does NOT query Assessment data.

### CoachCardView.swift (in Features/Coach/)
Displays recommendations. No "Why this?" affordance linking to citations.

### Citation.swift (120 lines)
`CitationRegistry` with 8 static citations. `Citation` struct has `url` field.

## Design

### 1. Feed Test Baselines into TrainingFacts

Extend `TrainingFacts` with assessment-derived fields:
```swift
// Strength baselines
var e1RMs: [String: Double]      // exerciseName → e1RM in kg
var latestAssessments: [AssessmentKind: AssessmentSummary]

// Cardio baselines
var estimatedVO2max: Double?     // ml/kg/min (best recent cardio test)
var estimatedMaxHR: Double?      // from age or test
var cardioZones: [CardioZone]?   // computed from maxHR
```

`TrainingFacts` init/builder queries the `Assessment` store for latest values per kind,
runs `AssessmentMath.summaries()`, and populates these fields.

### 2. Use Baselines in Recommendations

**Strength — %1RM working loads:**
When the coach prescribes a strength exercise:
- If e1RM exists for that exercise → compute `loadKg = e1RM * percentage` based on the
  scheme (e.g., 5x5 = 80-85% 1RM, hypertrophy = 65-75% 1RM).
- Set `SetTarget.loadKg` to the computed value.
- Set `Recommendation.citation` to the e1RM estimation citation + the percentage scheme
  citation.

**Cardio — HR zones:**
When the coach prescribes cardio:
- If VO2max and/or maxHR are known → compute zone boundaries.
- Prescribe target HR range in `Recommendation.detail`.
- If maxHR is estimated (age-based) rather than tested, note lower confidence.

**Missing baselines — prompt instead of guessing:**
If a needed baseline is missing:
```swift
Recommendation(
    kind: .progression,
    title: "Unlock load-based targets",
    action: "Run the Push-up Max test",
    detail: "We need your push-up baseline to prescribe appropriate volume.",
    citation: "",
    confidence: .low
)
```
The coach prompts the user to take the specific test rather than making up numbers.

### 3. "Why This?" Affordance on CoachCardView

Add a tappable "Why this?" element to `CoachCardView` that:
1. Reads `recommendation.citation` (currently a String).
2. Looks up the citation(s) in `CitationRegistry` by ID.
3. Presents a sheet/popover with:
   - Citation title, authors, year, source
   - URL link to the paper (if available)
   - Brief explanation of how the cited evidence drives this recommendation

**Data change:** `Recommendation.citation` should become `[String]` (array of citation IDs)
to support multiple sources per recommendation. Or add a `citationIds: [String]` field
alongside the existing `citation` string. **Recommendation:** add `citationIds: [String]`
(additive, keeps backward compat).

### 4. Citations on Each Test

Each `AssessmentDetailView` already links to an `AssessmentKind`. Wire:
- `kind.citationIds` → `CitationRegistry` lookup → display cited sources.
- Add a `citationIds` computed property on `AssessmentKind` returning the relevant
  registry keys (e.g., `cooperVo2max` for `.cooper12min`).

### 5. CitationDetailView

Create a reusable `CitationDetailView` that displays:
```
┌──────────────────────────────────────────┐
│  📄 Evidence                             │
│                                          │
│  Schoenfeld et al. (2021)                │
│  "Resistance Training Recommendations    │
│   to Maximize Muscle Hypertrophy..."     │
│  Sports Medicine, 51(4).                 │
│                                          │
│  [Open paper ↗]                          │
│                                          │
│  How this applies:                       │
│  This meta-analysis found that 10-20     │
│  weekly sets per muscle group maximizes   │
│  hypertrophy. Your current prescription  │
│  targets 12 sets/week for this muscle.   │
└──────────────────────────────────────────┘
```

## Data Model Deltas

**CadenceCore (additive):**
- `TrainingFacts`: add optional assessment-derived fields (no schema change — computed at
  runtime from Assessment queries).
- `Recommendation`: add `citationIds: [String]` field.
- `AssessmentKind`: add `citationIds` computed property.

No SwiftData model changes. No CloudKit impact.

## Implementation Steps

1. Extend `TrainingFacts` with assessment-derived fields + builder that queries Assessments
2. Update `RecommendationEngine` / `RecommendationRule` to use e1RM for %1RM loads
3. Update cardio recommendations to use VO2max/maxHR for zone prescriptions
4. Add "missing baseline" prompt recommendations
5. Add `citationIds` to `Recommendation` struct
6. Add `citationIds` computed property to `AssessmentKind`
7. Create `CitationDetailView` (reusable)
8. Add "Why this?" affordance to `CoachCardView` → presents CitationDetailView
9. Wire citations into `AssessmentDetailView`
10. `swift test` — new tests for %1RM load computation, zone calculation, missing-baseline prompts
11. `xcodebuild build`
12. Accessibility: VoiceOver on CitationDetailView, "Why this?" button

## Testing

- **Unit tests:** %1RM load computation (e.g., e1RM=100kg, 80% → loadKg=80)
- **Unit tests:** cardio zone computation from VO2max/maxHR
- **Unit tests:** missing-baseline prompt generation when Assessment store is empty
- **Unit tests:** citationIds on AssessmentKind returns correct registry keys
- `xcodebuild build`
- UI: verify "Why this?" opens citation sheet on CoachCardView
- UI: verify AssessmentDetailView shows cited sources
