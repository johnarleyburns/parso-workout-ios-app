# Plan: Bibliography + Unused Citations Integration

**Date:** 2026-07-07
**Depends on:** None (independent feature)
**Decisions locked:**
1. Bibliography section placed **below** the changelog entries in Coach Research Updates
2. `usageReason` kept in a **separate lookup** on `CitationRegistry` — `Citation` model stays pure
3. `lauersenInjuryPrevention2014` → **Coach About copy** (not flexibility claims)
4. Surface internal coach reasoning as much as possible — **"open door" principle**

---

## What this is

Two deliverables:
1. A full author-sorted bibliography in the Coach Research Updates screen, showing every citation with its title, authors, year, source, one-line "why we use it," and a tappable link to the full paper
2. Integrate the 4 defined-but-unused citations into the coaching engine and UI

---

## A. Bibliography in Coach Research Updates

### A1. Usage reason lookup (CadenceCore, pure)

Add a static dictionary to `CitationRegistry` in `Citation.swift` that maps citation IDs to one-line usage descriptions. The `Citation` struct stays untouched.

```swift
// CitationRegistry extension
public static let usageReasons: [String: String] = [
    "schoenfeld2021": "Loading recommendations — anchors the rep continuum for strength, hypertrophy, and endurance prescriptions.",
    "volumeDoseResponse": "Weekly sets-per-muscle dose-response — backs volume add/trim recommendations and per-part progress.",
    "frequencyMeta": "Spreading weekly volume across >=2 sessions per week improves per-set quality and recovery.",
    "oneRMEstimation": "Prediction equations for estimated 1RM — backs the e1RM formula picker and assessment retest prompts.",
    "rpeAutoregulation": "RIR-based RPE scale — backs autoregulation for load selection and proximity-to-failure prescriptions.",
    "cooperVo2max": "Cooper 12-minute run field test — backs the VO2max assessment protocol.",
    "wingateTest": "Wingate anaerobic test — backs the Wingate assessment and SIT/anaerobic training prescriptions.",
    "hiitVo2max": "Aerobic high-intensity intervals improve VO2max — backs HIIT prescriptions for cardiorespiratory fitness.",
    "rockportWalk": "Rockport 1-mile walk VO2max estimation — backs the walk assessment protocol.",
    "queensCollegeStep": "Queens College step test — backs the step-test assessment protocol.",
    "krieger2010": "Multi-set training superior to single-set for strength — backs the 5x5 program routine.",
    "rheaPeriodization": "Periodized training superior to non-periodized — backs the 5/3/1 program and periodization logic.",
    "calatayudBodyweight": "Bodyweight training effective for hypertrophy — backs the calisthenics program routine.",
    "channellOlympic": "Olympic lifting for strength development — backs the Olympic weightlifting program routine.",
    "zourdosDUP": "Daily undulating periodization — backs the DUP program routine.",
    "amirthalingamGVT": "German Volume Training effectiveness — backs the GVT routine and per-session volume warnings.",
    "williamsLinearPeriodization": "Linear periodization effectiveness — backs linear programs and the primary strength-block citation.",
    "tufanoCluster": "Cluster set training — backs the cluster-set program routine.",
    "ekelundActivityMortality2016": "Physical activity attenuates sitting-time mortality risk — backs aerobic-base recommendations and the 150-min floor.",
    "pellandDoseResponse2026": "Resistance training dose-response meta-regression — backs volume personalization and over-MRV trim warnings.",
    "ramosCampoSplit2024": "Full-body vs split routine effects on strength and hypertrophy — backs session-structure choices in the weekly plan.",
    "parejaBlancoRecovery2020": "48-hour same-lift recovery window after training to failure — backs the session eligibility deferral gates.",
    "sawMonitoring2016": "Self-reported measures trump objective monitoring — backs the readiness check-in system and recovery recommendations.",
    "meeusenOvertraining2013": "Overtraining prevention consensus — backs pain/illness safety gates, hard-day streak warnings, and rest-day prescriptions.",
    "schumannConcurrent2022": "Concurrent aerobic + strength compatibility — backs lower-body collision gates and two-a-day timing guidance.",
    "crowleyVO2Intensity2022": "Exercise intensity and VO2max improvement — backs VO2-interval session prescriptions.",
    "poonHIIT2024": "HIIT and cardiorespiratory fitness umbrella review — backs HIIT session candidates and prescriptions.",
    "mooreLeisureActivity2012": "Leisure-time activity and mortality — supplementary evidence for aerobic-base recommendations.",
    "aremDoseResponse2015": "Dose-response of physical activity and mortality — supplementary evidence for aerobic-base recommendations.",
    "saintMauriceSteps2020": "Daily step count and mortality — backs the step-health display and step-target guidance.",
    "leeAccelerometer2019": "Step volume/intensity in older women — supplementary evidence for step-health insights.",
    "halsonRecovery2014": "Monitoring training load to understand fatigue — supplementary evidence for recovery-readiness insights.",
    "drewFinchInjury2016": "Training load and injury/illness/soreness relationship — backs warnings about excessive volume and consecutive hard days.",
    "dupuyFatigue2018": "Evidence-based post-exercise recovery techniques — supplementary evidence for recovery-readiness insights.",
    "zourdosRIR2016": "Novel RPE scale measuring repetitions in reserve — backs the strength-intensity prescription pool.",
    "tanakaMaxHR2001": "Age-predicted maximal heart rate — backs threshold/tempo training when HR zones are estimated rather than tested.",
    "kaufmannThreshold2023": "HRV-derived thresholds for exercise intensity prescription — backs threshold/tempo training prescriptions.",
    "milanovicHIIT2015": "HIIT vs continuous endurance training for VO2max — supplementary evidence for VO2-interval prescriptions.",
    "slothSIT2013": "Sprint interval training effects on VO2max — backs the anaerobic/SIT opt-in prescription.",
    "buchheitLaursenHIIT2013": "HIIT programming: anaerobic energy and neuromuscular load — supplementary evidence for anaerobic training.",
    "konradStretchROM2024": "Chronic stretching effects on range of motion — backs stretch/mobility session candidates.",
    "behmStretching2016": "Acute stretching effects on performance and ROM — supplementary evidence for flexibility recommendations.",
    "lauersenInjuryPrevention2014": "Exercise interventions to prevent sports injuries — cited in Coach's safety-first philosophy (not tied to any single exercise modality).",
    "fieldFitnessReliability2022": "Reliability of field-based fitness tests — backs bodyweight benchmark assessments (push-up, pull-up, squat, hollow hold).",
    "tongPlank2014": "Sport-specific endurance plank test — backs the plank hold assessment protocol.",
    "murlasitsConcurrentSequence2018": "Concurrent strength-endurance training sequence — backs same-day cardio-timing guidance in schedule preferences.",
    "currierResistancePrescription2023": "Bayesian network meta-analysis of resistance training prescription — backs strength-block engine rules.",
]
```

### A2. Bibliography accessor (CadenceCore)

Add to `CitationRegistry`:

```swift
/// All citations, sorted by first author surname (scientific convention).
public static var bibliography: [Citation] {
    all.sorted { a, b in
        a.authors.localizedCaseInsensitiveCompare(b.authors) == .orderedAscending
    }
}
```

The `authors` field format is always "Surname, Other Authors & Last Author" — so alphabetical sort gives correct author-order for all 47 entries.

### A3. Bibliography section in Coach Research Updates (App UI)

Modify `CoachResearchUpdatesView.swift`:

1. Keep existing: header section + changelog `ForEach`
2. Add new `Section("Bibliography")` below the changelog
3. Each row renders:

```
Schoenfeld et al. (2021)
Loading Recommendations for Muscle Strength…
Sports 9(2):32.
Why: Loading recommendations — anchors the rep continuum...
Read the paper >
```

**Implementation:** Create a `BibliographyRow` view that takes a `Citation` and resolves its `usageReason` from `CitationRegistry.usageReasons[id]`. The row is a `NavigationLink` -> `CitationDetailView(citation: citation, context: usageReason)`. `CitationDetailView` already has:
- Full title, authors, year, source
- Optional "How this applies" section (pass `context: usageReason`)
- "Read the paper" `Link` that opens the URL in browser

This means tapping any bibliography entry shows the full citation detail screen with the usage reason as the "How this applies" context and a tappable web link at the bottom.

**Accessibility:** VoiceOver labels on each row combining author + title + usage reason. Dynamic Type via existing `scaledSystemFont`.

### A4. Update coach-kb-version.json

Add a new changelog entry bumping version to `2026.4.0`:

```json
{
  "version": "2026.4.0",
  "date": "2026-07-07",
  "title": "Bibliography - every study the Coach cites",
  "summary": "The Coach Research Updates screen now includes a full bibliography of all 47 peer-reviewed studies the coaching engine cites, ordered by author, each with a one-line explanation of why the Coach uses it and a direct link to the paper.",
  "citationIds": [
    "schoenfeld2021",
    "pellandDoseResponse2026",
    "ekelundActivityMortality2016"
  ]
}
```

---

## B. Integrating the Four Unused Citations

### B1. `hiitVo2max` -> VO2 training

**What it says:** Helgerud et al. (2007): 4x4 intervals at 90-95% HRmax improve VO2max more than moderate continuous training.

**Changes:**
1. Add `"hiitVo2max"` to `vo2TrainingPool` (Citation.swift line 594)
2. Add `"hiitVo2max"` to `citationIds` on VO2-interval session candidates in `CoachSession.swift` (line ~293, where `crowleyVO2Intensity2022` and `poonHIIT2024` are already cited)

**Effect:** Broader evidence base when the coach prescribes HIIT for VO2max. The coach already has this capability; this just anchors it more thoroughly.

### B2. `ramosCampoSplit2024` -> Session structure (OPEN DOOR)

**What it says:** Ramos-Campo et al. (2024): meta-analysis comparing full-body vs split routines for strength and hypertrophy.

**Changes:**
1. Add `"ramosCampoSplit2024"` to a new `sessionStructurePool` in Citation.swift with a new `EvidenceClaimCategory.sessionStructure`
2. After `CoachPlanOptimizer` builds a session, classify its structure:
   - **Full-body:** >=5 body parts covered -> reason: "Coach built a full-body session to spread weekly volume efficiently across fewer training days."
   - **Upper/Lower split:** predominantly upper or lower -> reason: "Coach focused this session on [upper/lower] body to allow adequate per-muscle volume within a single workout."
   - **Push/Pull split:** predominantly push or pull patterns -> reason: "Coach structured this as a [push/pull] session to group complementary movement patterns."
   - **Focused:** 1-2 parts -> reason: "Coach targeted [part names] specifically to close a weekly volume deficit."
3. Surface the structure classification + citation as an `ObservedFact` — a new `.sessionStructure` kind on the `ObservedFact.Kind` enum — on the `CoachDecision`
4. Render it in `CoachDecisionCardView` or `WhyThisTodayView` as a visible explanation

**"Open door" principle:** The user sees not just *what* the coach picked, but *why* it chose a full-body vs split format. This makes the optimizer's internal reasoning transparent.

### B3. `drewFinchInjury2016` -> Recovery warnings

**What it says:** Drew & Finch (2016): systematic review of training load and injury/illness/soreness.

**Changes:**
1. Add `"drewFinchInjury2016"` to `recoveryMonitoringPool` (Citation.swift line 636) — it currently sits only in the legacy `recoveryLoadPool`
2. Add it as a supplementary `citationId` on hard-day streak warnings in `CoachDecision.swift` (lines 705-712), alongside the existing `meeusenOvertraining2013`
3. Add it to the Coach Add-on Engine's fatigue-safety warnings in `CoachAddOnEngine.swift` (lines around 40, 111)

**Effect:** Warnings about consecutive hard days and excessive volume now cite a more specific load-injury paper in addition to the overtraining consensus.

### B4. `lauersenInjuryPrevention2014` -> Coach About copy

**What it says:** Lauersen et al. (2014): systematic review showing exercise interventions reduce sports injury risk.

**Constraint:** Must NOT appear in flexibility/ROM claims — the existing test at `RecommendationEngineTests.swift:433` explicitly guards this. The paper is about exercise-based injury prevention broadly, not stretching specifically.

**Changes:**
1. Add a new `injuryPreventionPool` with this citation (for future use, not tied to any specific claim category yet)
2. Add a new row to `CoachAboutView` "How it decides" section:

```swift
row("cross.case", "Safety-first guardrails",
    "Coach references published evidence on exercise-based injury prevention to inform its pain/illness gates, warm-up recommendations, and progressive-overload pacing. It never claims any single exercise or modality prevents all injuries — only that the overall approach is grounded in the evidence.")
```

3. Optionally add a `CitationLink` for `lauersenInjuryPrevention2014` below this row

**Effect:** The Coach About screen now explicitly cites the injury-prevention evidence behind its safety-first philosophy, without overclaiming about specific exercises.

---

## C. Testing

### Core tests (CadenceCore, `swift test`)

| Test | What it verifies |
|------|-----------------|
| `CitationIntegrityTests.testEveryUsageReasonResolves` | Every ID in `usageReasons` maps to a real citation in `all`; every citation in `all` has a non-empty `usageReason` |
| `CitationIntegrityTests.testBibliographySortedByAuthor` | `bibliography` is sorted correctly |
| `CoachKnowledgeBaseTests.testNewKBEntryLoads` | v2026.4.0 entry exists and its citationIds resolve |
| `RecommendationEngineTests.testHIITVo2maxInVo2Pool` | `hiitVo2max` is in `vo2TrainingPool` |
| `RecommendationEngineTests.testDrewFinchInRecoveryPool` | `drewFinchInjury2016` is in `recoveryMonitoringPool` |
| `RecommendationEngineTests.testLauersenNotInFlexibilityPool` | Existing test remains green — `lauersenInjuryPrevention2014` still NOT in `flexibilityROMPool` |
| `CoachPlanOptimizerTests.testSessionStructureFactSurfaced` | Full-body/split classification produces the expected `ObservedFact` |

### Existing test assertion to preserve

`RecommendationEngineTests.testFlexibilityRuleUsesROMCitationAndNoInjuryPreventionOverclaim` (line 426) — must remain green. `lauersenInjuryPrevention2014` must never appear in a flexibility/ROM claim.

---

## D. Files touched

| File | Change |
|------|--------|
| `CadenceCore/…/Citation.swift` | Add `usageReasons` dict + `bibliography` accessor + `sessionStructurePool` + `injuryPreventionPool` + add `hiitVo2max` to `vo2TrainingPool` + add `drewFinchInjury2016` to `recoveryMonitoringPool` + new `EvidenceClaimCategory.sessionStructure` |
| `CadenceCore/…/CoachSession.swift` | Add `hiitVo2max` `citationIds` to VO2-interval candidates |
| `CadenceCore/…/CoachDecision.swift` | New `ObservedFact.Kind.sessionStructure` + populate from optimizer output + add `drewFinchInjury2016` to hard-day warnings |
| `CadenceCore/…/CoachPlanOptimizer.swift` | Session-structure classification logic (full-body / upper-lower / push-pull / focused) + produce structure fact |
| `CadenceCore/…/CoachAddOnEngine.swift` | Add `drewFinchInjury2016` to fatigue-safety warnings |
| `CadenceCore/…/Resources/coach-kb-version.json` | New v2026.4.0 bibliography entry |
| `Cadence/…/CoachResearchUpdatesView.swift` | Add Bibliography section + `BibliographyRow` |
| `Cadence/…/CoachAboutView.swift` | Add safety-first row citing `lauersenInjuryPrevention2014` |
| `CadenceCore/Tests/…/CitationIntegrityTests.swift` | New `usageReasons` + `bibliography` tests |
| `CadenceCore/Tests/…/CoachKnowledgeBaseTests.swift` | Extend for v2026.4.0 entry |
| `CadenceCore/Tests/…/RecommendationEngineTests.swift` | New pool-membership assertions |
| `CadenceCore/Tests/…/CoachPlanOptimizerTests.swift` | Session-structure fact test |
| `docs/CITATIONS.md` | Sync with `usageReasons` — every ID gets its usage explanation |

---

## E. Phasing

| Phase | Deliverable | Dependencies | Branch |
|-------|------------|--------------|--------|
| 1 | `usageReasons` dict + `bibliography` accessor + integrity tests | None | `feat/bibliography` (off `main`) |
| 2 | Bibliography section in Coach Research Updates + KB entry | Phase 1 | Same branch |
| 3 | Integrate `hiitVo2max` + `drewFinchInjury2016` + `lauersenInjuryPrevention2014` | Phase 1 | Same branch |
| 4 | Integrate `ramosCampoSplit2024` with session-structure surfacing | Phase 1 | Same branch |
| 5 | Update `CITATIONS.md` + final test pass | Phase 4 | Same branch |

All phases can ship in one PR — they're small, additive, and independently testable.

---

## F. Verification

- `cd CadenceCore && swift test` — all tests green, new tests included
- `xcodebuild -project Cadence/Cadence.xcodeproj -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build` — BUILD SUCCEEDED
- Manual on device/sim: Coach Research Updates -> scroll past changelog -> see bibliography sorted by author -> tap any entry -> see full citation + usage reason + "Read the paper" link -> tap link -> paper opens in browser
- Manual: Coach About -> see new safety-first row with injury prevention citation
- Manual: Why This Today -> see session-structure explanation when coach picks full-body vs split
