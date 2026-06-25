# Coach Expert System Evidence Upgrade Plan

**Date:** 2026-06-25  
**Stream:** `plans/field-testing/2026-06-25/`  
**Scope:** Upgrade Coach from a lightly cited strength/cardio heuristic into a claim-specific, multi-system, evidence-backed coaching engine covering strength, hypertrophy, aerobic base, VO2 work, threshold/lactate work, anaerobic work, flexibility/mobility, concurrent-training conflicts, recovery, and assessment quality.

## Product Goal

Coach should produce recommendations that are:

1. Specific: the user sees exactly what to train, why now, what system it targets, and what to do next.
2. Evidence-mapped: every claim is tied to a study that actually supports that claim.
3. Multi-system: weekly planning balances strength, hypertrophy, aerobic base, high-intensity aerobic work, threshold/lactate work, anaerobic work, flexibility, and recovery.
4. Conservative: Coach never diagnoses medical conditions, never overstates precision from noisy field tests, and never auto-prescribes high-risk all-out work.
5. Testable: every rule, citation ID, and explanation is covered by unit or UI tests.

## Current Problems

### Citation And Metadata Problems

- `wingateTest` has the wrong DOI in `CadenceCore/Sources/CadenceCore/Citation.swift`. PubMed record `3324256` lists `10.2165/00007256-198704060-00001`; the registry currently uses `...00005`.
- `pellandDoseResponse2026` points to PubMed `41343037`, but the registry authors/title are wrong. The PubMed record is Pelland, Remmert, Robinson, Hinson & Zourdos, "The Resistance Training Dose Response: Meta-Regressions Exploring the Effects of Weekly Volume and Frequency on Muscle Hypertrophy and Strength Gains."
- `crowleyVO2Intensity2022` source metadata is wrong. PubMed `38655159` is in `Translational Sports Medicine`, title "The Effect of Exercise Training Intensity on VO(2)max in Healthy Adults: An Overview of Systematic Reviews and Meta-Analyses."
- `poonHIIT2024` source metadata is wrong. PubMed `38760916` is in `Scandinavian Journal of Medicine & Science in Sports`, title "High-intensity interval training and cardiorespiratory fitness in adults: An umbrella review..."
- `sawMonitoring2016` metadata should be checked. PubMed `26423706` is Saw, Main & Gastin, "Monitoring the athlete training response: subjective self-reported measures trump commonly used objective measures", in `British Journal of Sports Medicine`.
- Some assessments return no citation IDs: push-up max, pull-up max, bodyweight squat max, plank hold, hollow hold.
- `run1_5mile` currently reuses `cooperVo2max`. This may be acceptable only if the protocol/equation is explicitly traced to a published field-test source; otherwise add a distinct citation or remove equation-specific claims.

### Claim Mapping Problems

- `WhyThisTodayView` uses the aerobic citation pool for the "strength days this week" claim. That inflates citation count without improving accuracy.
- Step-count studies are in the same pool as moderate-equivalent-minute claims. They should not cite the 150 minute threshold unless the claim is about step count.
- Most easy/moderate aerobic sessions cite only Ekelund 2016, even when the claim is not mortality/sedentary risk.
- `recovery.stretch` has no citations despite being surfaced as a Coach candidate.
- Citation pools rotate by date/hash, but there is no type system that prevents a pool for one claim class from being used for another.

### Coaching Specificity Problems

- Session selection is mostly based on:
  - `strengthDays < 2`
  - `moderateEquivalentMinutes < 150`
  - `consecutiveHardDays`
  - fixed recovery windows
  - user preferences
- Prescriptive recommendations are currently limited to:
  - double progression
  - monitoring/deload after declining e1RM
  - add volume below fixed volume landmarks
  - moderate aerobic starter
  - VO2 interval suggestion after declining VO2 assessment
  - missing baseline prompt
- The coach does not track or prescribe:
  - threshold/lactate work
  - anaerobic/SIT work as an opt-in lane
  - flexibility/mobility as a trainable quality
  - block-level strength programming
  - load spikes
  - readiness-adjusted session selection
  - assessment freshness per system
  - uncertainty from HRmax estimates and field tests

## Non-Goals

- Do not add an LLM, server, account system, telemetry, or external inference.
- Do not make medical diagnoses or say the user is "overtrained."
- Do not auto-prescribe all-out sprint interval training.
- Do not cite public-health guidelines as the source for Coach prescriptions when a peer-reviewed study is available.
- Do not add a large UI redesign in this workstream. Update only the surfaces needed to expose the new claims and citations.
- Do not remove existing conservative recovery gates until replacement logic is tested.

## Evidence Registry Target State

Add or correct citations in `CitationRegistry`, then mirror them in `docs/CITATIONS.md`.

### Strength And Hypertrophy

| Citation ID | Source | Used For |
|---|---|---|
| `schoenfeld2021` | PMID `33671664`, PMC `PMC7927075`, DOI `10.3390/sports9020032` | Load/rep continuum, strength vs hypertrophy vs endurance framing |
| `volumeDoseResponse` | PMID `27433992`, DOI `10.1080/02640414.2016.1210197` | Initial weekly set dose-response |
| `pellandDoseResponse2026` | PMID `41343037`, DOI `10.1007/s40279-025-02344-w` | Updated volume/frequency meta-regression |
| `frequencyMeta` | PMID `30558493`, DOI `10.1080/02640414.2018.1555906` | Frequency as volume distribution, not independent magic |
| `rpeAutoregulation` | PMID `27531969`, PMC `PMC4961270` | RIR/RPE autoregulation |
| `zourdosRIR2016` | PMID `26049792`, DOI `10.1519/JSC.0000000000001049` | Resistance-training-specific RPE/RIR scale validation |
| `williamsLinearPeriodization` | PMID `28497285`, DOI `10.1007/s40279-017-0734-y` | Periodized vs non-periodized strength training |
| `rheaPeriodization` | PMID `15673040`, DOI `10.1080/02701367.2004.10609174` | Periodized strength and power programming |

### Aerobic Health, Base, VO2, Threshold

| Citation ID | Source | Used For |
|---|---|---|
| `ekelundActivityMortality2016` | PMID `27475271`, DOI `10.1016/S0140-6736(16)30370-1` | Physical activity volume and mortality/sitting-time risk |
| `mooreLeisureActivity2012` | PMID `23139642`, PMC `PMC3491006` | Moderate/vigorous activity dose-response and mortality |
| `aremDoseResponse2015` | PMID `25844730`, PMC `PMC4451435` | Dose-response and diminishing returns for leisure activity |
| `saintMauriceSteps2020` | PMID `32207799`, PMC `PMC7093766` | Step count and mortality |
| `leeAccelerometer2019` | PMID `31141585`, PMC `PMC6547157` | Step count and mortality in older women |
| `crowleyVO2Intensity2022` | PMID `38655159`, PMC `PMC11022784` | Exercise intensity and VO2max overview |
| `poonHIIT2024` | PMID `38760916`, DOI `10.1111/sms.14652` | HIIT/cardiorespiratory fitness umbrella review |
| `milanovicHIIT2015` | PMID `26243014`, DOI `10.1007/s40279-015-0365-0` | HIIT vs continuous training for VO2max |
| `tanakaMaxHR2001` | PMID `11153730`, DOI `10.1016/s0735-1097(00)01054-8` | Age-predicted HRmax fallback and uncertainty label |
| `kaufmannThreshold2023` | PMID `37462761`, PMC `PMC10354346` | Threshold/HRV/ventilatory/lactate threshold agreement and uncertainty |

### Anaerobic And High-Intensity Work

| Citation ID | Source | Used For |
|---|---|---|
| `wingateTest` | PMID `3324256`, DOI `10.2165/00007256-198704060-00001` | Wingate methodology/reliability/validity |
| `slothSIT2013` | PMID `23889316`, DOI `10.1111/sms.12092` | Sprint interval training effects on VO2max/aerobic performance |
| `buchheitLaursenHIIT2013` | PMID `23832851`, DOI `10.1007/s40279-013-0066-5` | Anaerobic energy, neuromuscular load, HIIT programming |

### Flexibility, Mobility, Warm-Up, Injury Risk

| Citation ID | Source | Used For |
|---|---|---|
| `konradStretchROM2024` | PMID `37301370`, PMC `PMC10980866` | Chronic stretching and range-of-motion gains |
| `behmStretching2016` | PMID `26642915`, DOI `10.1139/apnm-2015-0235` | Acute stretching, performance, ROM, injury claims |
| `lauersenInjuryPrevention2014` | PMID `24100287`, DOI `10.1136/bjsports-2013-092538` | Exercise interventions and sports-injury prevention; use for strength/proprioceptive warm-up claims, not static stretching alone |

### Recovery, Readiness, Concurrent Training

| Citation ID | Source | Used For |
|---|---|---|
| `halsonRecovery2014` | PMID `25200666`, PMC `PMC4213373` | Training load monitoring and fatigue |
| `sawMonitoring2016` | PMID `26423706`, PMC `PMC4789708` | Subjective self-report monitoring |
| `dupuyFatigue2018` | PMID `29755363`, PMC `PMC5932411` | Post-exercise recovery technique effects |
| `schumannConcurrent2022` | PMID `34757594`, PMC `PMC8891239` | Concurrent aerobic and strength compatibility |
| `meeusenOvertraining2013` | PMID `23247672` | Overtraining consensus and safety caveats |

### Field Tests And Assessments

| Citation ID | Source | Used For |
|---|---|---|
| `oneRMEstimation` | Existing | e1RM/rep-max strength tests |
| `cooperVo2max` | Existing | Cooper 12-minute test |
| `rockportWalk` | Existing | Rockport walk test |
| `queensCollegeStep` | Existing | Queens College step test |
| `fieldFitnessReliability2022` | PMID `35064915`, DOI `10.1007/s40279-021-01635-2` | General field-based adult fitness test reliability; use only as a fallback for bodyweight endurance tests |
| `tongPlank2014` | PMID `23850461`, DOI `10.1016/j.ptsp.2013.03.003` | Plank/core endurance test support |

If a bodyweight test cannot be mapped to a defensible published source, mark it as "self-tracked benchmark" and cite only the broader field-test reliability source. Do not claim population validity.

## Architecture Plan

### A. Citation QA And Integrity Gate

Files:

- `CadenceCore/Sources/CadenceCore/Citation.swift`
- `docs/CITATIONS.md`
- `CadenceCore/Tests/CadenceCoreTests/CitationIntegrityTests.swift`
- `CadenceCore/Tests/CadenceCoreTests/ScienceCopyTests.swift`

Tasks:

1. Correct the metadata issues listed above.
2. Add all new citations needed by this plan.
3. Split `CitationRegistry.aerobicPool` into claim-specific pools:
   - `activityMinutesHealthPool`
   - `stepsHealthPool`
   - `vo2TrainingPool`
   - `thresholdTrainingPool`
   - `strengthFrequencyPool`
   - `strengthVolumePool`
   - `recoveryMonitoringPool`
   - `flexibilityROMPool`
   - `anaerobicTrainingPool`
4. Add a typed claim category enum:

```swift
public enum EvidenceClaimCategory: String, Sendable, Codable {
    case activityMinutesHealth
    case stepsHealth
    case strengthFrequency
    case strengthVolume
    case strengthIntensity
    case periodization
    case aerobicBase
    case vo2Training
    case thresholdTraining
    case anaerobicTraining
    case flexibilityROM
    case recoveryMonitoring
    case concurrentTraining
    case fieldTestValidity
}
```

5. Make `EvidenceClaim` carry `category` instead of a raw `poolId`.
6. Add a resolver:

```swift
public static func citationPool(for category: EvidenceClaimCategory) -> CitationPool
```

7. Add tests:
   - `testEveryCitationIdIsUnique`
   - `testEveryCitationHasResolvablePublicUrl`
   - `testCorrectedCitationMetadata`
   - `testEveryPoolIdResolves`
   - `testNoClaimUsesMismatchedCitationCategory`
   - `testEveryAssessmentKindHasCitationPolicy`
   - `testEveryCoachSessionCandidateHasCitationIdsUnlessRestOrEmptyLaunch`
   - `testEveryDecisionReasonAndWarningCitationIdResolves`

Acceptance criteria:

- No coach-visible claim can use a citation pool from the wrong category.
- No raw citation ID appears in UI.
- `recovery.stretch` has at least one ROM/flexibility citation.
- Assessment tests with weak validation are explicitly labeled as personal benchmarks.

### B. Multi-System Fact Model

Files:

- `CadenceCore/Sources/CadenceCore/CoachFacts.swift`
- `CadenceCore/Sources/CadenceCore/TrainingFacts.swift`
- `CadenceCore/Sources/CadenceCore/TrainingEvent.swift`
- New: `CadenceCore/Sources/CadenceCore/SystemLoad.swift`
- New: `CadenceCore/Sources/CadenceCore/ReadinessCheckIn.swift` if no existing readiness model exists
- Tests in `CoachFactsTests.swift`, `TrainingFactsTests.swift`

Add types:

```swift
public enum TrainingSystem: String, Sendable, Codable, CaseIterable {
    case maximalStrength
    case hypertrophy
    case strengthEndurance
    case aerobicBase
    case vo2max
    case threshold
    case anaerobicPower
    case flexibility
    case recovery
}

public struct SystemLoad: Sendable, Equatable {
    public let system: TrainingSystem
    public let trailing7dExposures: Double
    public let trailing28dExposures: Double
    public let daysSinceLastExposure: Int?
    public let lastHardExposureAt: Date?
    public let trend: TrendDirection?
    public let confidence: FactConfidence
}

public struct ReadinessSnapshot: Sendable, Equatable {
    public let soreness: Int?
    public let sleepQuality: Int?
    public let stress: Int?
    public let motivation: Int?
    public let painConcern: Bool
    public let capturedAt: Date?
    public var confidence: FactConfidence
}
```

Add to `CoachFacts`:

- `systemLoads: [TrainingSystem: SystemLoad]`
- `readiness: ReadinessSnapshot?`
- `assessmentCoverage: [TrainingSystem: AssessmentCoverage]`
- `loadSpikeFlags: [LoadSpikeFlag]`
- `zoneSource: CardioZoneSource`

Add to `TrainingFacts`:

- per-lift repeated decline count
- per-lift sessions since last deload
- per-body-part volume trend
- per-body-part response trend
- aerobic minutes by intensity bucket: easy, moderate, threshold, VO2, anaerobic
- recent HIIT/SIT count
- flexibility/mobility minutes or sessions

Rules for event classification:

- Strength sets:
  - Heavy low-rep high-load sets count toward `maximalStrength`.
  - Moderate/hard volume counts toward `hypertrophy`.
  - High-rep local work counts toward `strengthEndurance`.
- Aerobic workouts:
  - Easy/moderate continuous work counts toward `aerobicBase`.
  - Vigorous intervals over 2 minutes count toward `vo2max`.
  - Sustained hard efforts near zone 4 or RPE 7-8 count toward `threshold`.
  - All-out intervals under 60 seconds count toward `anaerobicPower`.
- Mobility/recovery sessions:
  - Stretch/mobility counts toward `flexibility`.
  - Easy walk/recovery counts toward `recovery` and light aerobic base, but not threshold/VO2.

Acceptance criteria:

- Coach can explain which systems are stale, which are loaded, and which are blocked.
- Future recommendations no longer depend only on `strengthDays` and `moderateEquivalentMinutes`.
- Existing tests for old weekly balance still pass.

### C. Recommendation Engine Rule Expansion

Files:

- `CadenceCore/Sources/CadenceCore/RecommendationRule.swift`
- `CadenceCore/Sources/CadenceCore/Recommendation.swift`
- `CadenceCore/Sources/CadenceCore/TrainingGoal.swift`
- New: `CadenceCore/Sources/CadenceCore/CoachRuleSupport.swift`
- Tests in `RecommendationEngineTests.swift`, `ScienceCopyTests.swift`

Add `RecommendationKind` cases:

```swift
case strengthBlock
case volumeAdjust
case periodizedVariation
case aerobicBase
case vo2Intervals
case thresholdTempo
case anaerobicOptIn
case flexibility
case recoveryReadiness
case assessmentPrompt
```

Add optional fields to `Recommendation`:

- `system: TrainingSystem`
- `evidenceCategory: EvidenceClaimCategory`
- `whyNowFacts: [String]`
- `riskNotes: [String]`
- `uncertainty: FactConfidence`
- `minimumEligibility: [String]`

Rules to add:

#### C1. Strength Block Rule

Trigger:

- User has at least 2 weeks of strength history or has completed baseline strength assessments.

Output:

- A 4-8 week block target:
  - strength goal: heavy work plus lower-volume accessories
  - hypertrophy goal: volume progression with RIR target
  - endurance goal: higher-rep local endurance and aerobic support

Citations:

- `schoenfeld2021`
- `williamsLinearPeriodization`
- `rpeAutoregulation`

Tests:

- `testStrengthBlockUsesGoalSpecificRepAndIntensityTargets`
- `testStrengthBlockCitesPeriodizationAndLoadContinuum`
- `testStrengthBlockDoesNotOverrideRecoveryGates`

#### C2. Volume Personalization Rule

Trigger:

- Body part below starting range and not improving, or above high range with poor readiness/stalled performance.

Output:

- Add, hold, or reduce sets.
- Use current personal response before generic MEV/MRV labels.

Citations:

- `volumeDoseResponse`
- `pellandDoseResponse2026`
- `frequencyMeta`

Tests:

- `testVolumeIncreaseRequiresLowVolumeAndNoRecoveryBlock`
- `testHighVolumePoorReadinessSuggestsHoldOrReduce`
- `testFrequencyClaimUsesFrequencyCitationNotVolumeCitation`

#### C3. Aerobic Base Rule

Trigger:

- Low aerobic base exposure or no recent easy/moderate aerobic work.

Output:

- 20-45 minutes easy/moderate work, progress duration before intensity.
- Use health-volume citations only for health floor claims.

Citations:

- `ekelundActivityMortality2016`
- `mooreLeisureActivity2012`
- `aremDoseResponse2015`

Tests:

- `testAerobicBaseUsesActivityMinutesHealthCitations`
- `testAerobicBaseDoesNotClaim150MinutesIsOptimal`
- `testBeginnerGetsDurationBeforeIntensity`

#### C4. VO2 Interval Rule

Trigger:

- VO2max declined, VO2 system stale, or user goal includes cardiorespiratory improvement.
- Require base exposure and no recovery block.

Output:

- Long intervals such as 4x4, 3x5, or equivalent.
- 1 session/week default, 2 only if load and readiness support it.

Citations:

- `crowleyVO2Intensity2022`
- `poonHIIT2024`
- `milanovicHIIT2015`

Tests:

- `testVO2RuleRequiresBaseOrIntermediateExperience`
- `testVO2RuleBlockedAfterLowerBodyCollision`
- `testVO2RuleCitesVO2TrainingPool`

#### C5. Threshold/Lactate Rule

Trigger:

- Aerobic base exists, VO2 is not the current limiter, and threshold system is stale.
- Prefer RPE or tested threshold. If only HRmax is estimated, mark confidence low.

Output:

- Tempo/threshold prescription such as 2x10 min steady-hard or 20 min continuous tempo.

Citations:

- `kaufmannThreshold2023`
- optionally `tanakaMaxHR2001` when HRmax is estimated.

Tests:

- `testThresholdRuleAddsLowConfidenceWhenOnlyAgeEstimatedHRMax`
- `testThresholdRuleUsesThresholdCitation`
- `testThresholdRuleDoesNotUseMortalityCitation`

#### C6. Anaerobic Opt-In Rule

Trigger:

- Advanced user, anaerobic assessment exists or user explicitly opts into anaerobic development.
- No recent high-fatigue lower-body strength, VO2 intervals, or SIT session.

Output:

- Offer, not auto-prescribe, SIT/REHIT/short sprints.
- Use clear warning: high fatigue, stop for pain/dizziness, requires user opt-in.

Citations:

- `wingateTest`
- `slothSIT2013`
- `buchheitLaursenHIIT2013`

Tests:

- `testSITIsNeverAutoPrimaryWithoutOptIn`
- `testAnaerobicOptInRequiresAdvancedOrExplicitPreference`
- `testAnaerobicBlockedAfterRecentHardLowerBody`
- `testAnaerobicClaimsAreCited`

#### C7. Flexibility/Mobility Rule

Trigger:

- No mobility/flexibility exposure in trailing 7 days, user selects flexibility goal, or recovery day with no hard-training eligibility.

Output:

- 10-20 minutes mobility/stretching.
- Claim only ROM/flexibility benefits unless paired with broader warm-up/injury-prevention exercises.

Citations:

- `konradStretchROM2024`
- `behmStretching2016`
- `lauersenInjuryPrevention2014` only for broader injury-prevention exercise programs.

Tests:

- `testRecoveryStretchHasFlexibilityCitation`
- `testStretchingCopyDoesNotClaimItPreventsAllInjuries`
- `testFlexibilityRuleUsesROMCitation`

#### C8. Recovery And Readiness Rule

Trigger:

- Consecutive hard days, load spike, poor readiness, soreness, sleep/stress flags, repeated e1RM decline, or unknown import.

Output:

- Rest, easy aerobic, mobility, or reduced-load session.
- State uncertainty.
- Never diagnose overtraining.

Citations:

- `halsonRecovery2014`
- `sawMonitoring2016`
- `dupuyFatigue2018`
- `meeusenOvertraining2013`

Tests:

- `testPoorReadinessDowngradesHardSession`
- `testRepeatedDeclinePlusPoorReadinessSuggestsDeload`
- `testRecoveryCopyDoesNotDiagnoseOvertraining`
- `testRecoveryUsesMonitoringCitations`

#### C9. Assessment Prompt Rule

Trigger:

- Missing or stale baseline for the system Coach wants to prescribe.

Output:

- Specific prompt: e1RM, VO2 field test, Wingate, flexibility benchmark, or readiness check-in.

Citations:

- test-specific citations only.

Tests:

- `testMissingVO2BaselinePromptsCardioAssessment`
- `testMissingStrengthBaselinePromptsE1RM`
- `testStaleAssessmentPromptsRetest`
- `testAssessmentPromptCitesAssessmentSource`

### D. Coach Session Candidate And Scoring Rewrite

Files:

- `CadenceCore/Sources/CadenceCore/CoachSession.swift`
- `CadenceCore/Sources/CadenceCore/CoachDecision.swift`
- `CadenceCore/Sources/CadenceCore/SessionEligibilityPolicy.swift`
- Tests in `CoachDecisionEngineTests.swift`, `SessionEligibilityPolicyTests.swift`

Replace `scoreSessionBase` with a system-need score:

```swift
public struct SessionScoreBreakdown: Sendable, Equatable {
    public let systemNeed: Int
    public let recoveryPenalty: Int
    public let preferenceBonus: Int
    public let sameDayPenalty: Int
    public let confidencePenalty: Int
    public let reasons: [EvidenceClaim]
}
```

Scoring inputs:

- system stale score
- weekly balance score
- assessment trend score
- readiness/recovery score
- same-day repetition penalty
- user preference
- high-impact avoidance
- uncertainty penalty

Candidate changes:

- Every candidate gets:
  - `systemsTrained: [TrainingSystem]`
  - `evidenceCategory: EvidenceClaimCategory`
  - non-empty `citationIds` unless it is pure rest/fallback
- Add candidates:
  - threshold tempo
  - mobility/flexibility
  - anaerobic opt-in option
  - assessment session
  - reduced-load strength
- Keep existing easy/moderate aerobic and strength sessions.

Eligibility changes:

- Keep pain/illness safety gate.
- Keep lower-body collision gate, but distinguish:
  - easy low-impact aerobic allowed
  - threshold/VO2/anaerobic blocked after recent hard lower-body work
- Add load spike/readiness gates.
- Add SIT opt-in gate.

Tests:

- `testSystemNeedScoresPreferStaleSystem`
- `testStrengthDaysClaimUsesStrengthFrequencyCitation`
- `testAerobicMinutesClaimUsesActivityMinutesCitation`
- `testStepClaimUsesStepCitationOnly`
- `testVO2CandidateUsesVO2Citations`
- `testThresholdCandidateUsesThresholdCitation`
- `testMobilityCandidateUsesROMCitation`
- `testSITCandidateIsAlternativeOnlyUnlessOptedIn`
- `testPreferenceCannotOverrideSafetyOrRecovery`

Acceptance criteria:

- Why This Today can show a score breakdown with citations next to each reason.
- The primary recommendation changes when a system is stale, not only when strength days/aerobic minutes are below fixed floors.
- Alternatives remain eligible and explainable.

### E. Assessment Citation And Uncertainty Upgrade

Files:

- `CadenceCore/Sources/CadenceCore/Assessment.swift`
- `CadenceCore/Sources/CadenceCore/AssessmentMath.swift`
- `CadenceCore/Sources/CadenceCore/CardioMath.swift`
- `Cadence/Cadence/Features/Plan/AssessmentDetailView.swift`
- Tests in `AssessmentMathTests.swift`, `CitationIntegrityTests.swift`

Tasks:

1. Add citations for all assessment kinds or explicit "personal benchmark" policy.
2. Add `AssessmentKind.evidencePolicy`:

```swift
public enum AssessmentEvidencePolicy: Sendable, Equatable {
    case validated(citationIds: [String])
    case fieldEstimate(citationIds: [String], uncertainty: FactConfidence)
    case personalBenchmark(citationIds: [String], caveat: String)
}
```

3. Add uncertainty labels:
   - direct e1RM: moderate
   - low-rep e1RM: moderate/high depending reps
   - high-rep e1RM: low/moderate
   - VO2 field test: moderate
   - wearable/manual VO2: low unless source details available
   - bodyweight max/hold tests: personal benchmark unless source is strong
4. Add `tanakaMaxHR2001` citation wherever default HRmax is used.
5. Ensure `CardioMath.hrZone` and default max HR explanations are visible where prescriptions use HR zones.

Tests:

- `testEveryAssessmentKindHasEvidencePolicy`
- `testBodyweightAssessmentsAreBenchmarksWhenWeaklyValidated`
- `testAgeEstimatedHRMaxAddsLowConfidence`
- `testCardioZonePrescriptionCitesMaxHREquationWhenEstimated`

Acceptance criteria:

- The coach never gives a highly specific HR zone without saying whether max HR was tested or estimated.
- The app does not pretend bodyweight benchmark tests are lab-grade validity measures.

### F. UI Explanation Updates

Files:

- `Cadence/Cadence/Features/Coach/WhyThisTodayView.swift`
- `Cadence/Cadence/Features/Coach/CoachDecisionCardView.swift`
- `Cadence/Cadence/Features/Coach/CoachCardView.swift`
- `Cadence/Cadence/Features/Coach/CitationDetailView.swift`
- `Cadence/Cadence/Features/Progress/ProgressView.swift`

Tasks:

1. Replace generic claims with system-specific claims:
   - Strength frequency
   - Strength volume/intensity
   - Aerobic base
   - VO2/threshold/anaerobic
   - Recovery/readiness
   - Flexibility
2. Show `system` and `confidence` on recommendations.
3. Show citations next to each claim, not in a generic evidence bucket.
4. Add caveat display for low-confidence HR zones and field tests.
5. Add a compact "Training systems this week" section:
   - Strength
   - Aerobic base
   - Hard aerobic
   - Mobility
   - Recovery
6. Ensure all strings fit on small screens.

UI tests:

- `WhyThisTodayUITests.testClaimsUseSpecificCitationLinks`
- `WhyThisTodayUITests.testLowConfidenceZoneShowsCaveat`
- `WhyThisTodayUITests.testMobilityRecommendationShowsScience`
- `CoachCardUITests.testRecommendationShowsSystemAndConfidence`

Acceptance criteria:

- No broad citation pool appears next to an unrelated claim.
- A user can tell whether Coach is recommending work for strength, aerobic base, VO2, threshold, anaerobic, flexibility, or recovery.

### G. Documentation And Maintenance

Files:

- `docs/CITATIONS.md`
- `README.md`
- `CLAUDE.md`
- `docs/REQUIREMENTS.md`

Tasks:

1. Update `docs/CITATIONS.md` to match `CitationRegistry.all`.
2. Add a "Claim classes" section explaining which citations may support which claims.
3. Add a maintainer rule:
   - New coaching claims require a citation category.
   - New citation categories require tests.
   - Public-health outcome studies cannot cite performance prescriptions.
4. Update README copy from "30+ citations" only if count changes.
5. Add a pre-merge checklist:
   - `swift test`
   - citation integrity tests
   - `rg -n "citationIds: \\[\\]" CadenceCore/Sources/CadenceCore`
   - `rg -n "CitationRegistry\\.aerobicPool|poolId: \"aerobic\"" .`

## Implementation Order

### Phase 1: Citation QA And Guardrails

Implement A and E minimal citation-policy changes first.

Deliverables:

- Correct citation metadata.
- New citations registered.
- `docs/CITATIONS.md` updated.
- Integrity tests added.
- Assessment citation policy added.

Run:

- `swift test --filter CitationIntegrityTests`
- `swift test --filter ScienceCopyTests`
- `swift test --filter AssessmentMathTests`

### Phase 2: Multi-System Facts

Implement B without changing Coach primary behavior yet.

Deliverables:

- `TrainingSystem`
- `SystemLoad`
- `ReadinessSnapshot`
- event classification into systems
- tests for classification and rolling windows

Run:

- `swift test --filter CoachFactsTests`
- `swift test --filter TrainingFactsTests`

### Phase 3: Recommendation Rules

Implement C rules behind the existing deterministic `RecommendationEngine`.

Deliverables:

- New `RecommendationKind` cases.
- New rule tests.
- No UI changes required yet.

Run:

- `swift test --filter RecommendationEngineTests`
- `swift test --filter ScienceCopyTests`

### Phase 4: Decision Scoring And Candidates

Implement D and update `CoachDecision`.

Deliverables:

- score breakdown
- system-aware candidates
- typed evidence claims
- updated eligibility gates

Run:

- `swift test --filter CoachDecisionEngineTests`
- `swift test --filter SessionEligibilityPolicyTests`
- `swift test --filter CoachPreferenceProfileTests`

### Phase 5: UI Handoff

Implement F.

Deliverables:

- Why This Today claim-specific sources
- system/confidence display
- low-confidence caveats
- updated UI tests

Run:

- relevant `xcodebuild test` or existing UI test command for Coach/Why This Today
- at minimum, run existing Coach UI tests locally if available

### Phase 6: Docs And Final Verification

Implement G and run full regression.

Run:

- `swift test`
- citation searches:
  - `rg -n "citationIds: \\[\\]" CadenceCore/Sources/CadenceCore`
  - `rg -n "poolId: \"aerobic\"|aerobicPool" .`
  - `rg -n "overtrained|overtraining" CadenceCore/Sources Cadence/Cadence/Features`

## Acceptance Criteria For The Whole Workstream

- Every Coach-visible recommendation, warning, deferred reason, assessment, and "Why this won" claim has a resolvable citation or an explicit non-recommendation fallback policy.
- Every citation displayed beside a claim supports that claim class.
- Coach can recommend at least one session or prompt for each system:
  - maximal strength
  - hypertrophy/volume
  - strength endurance
  - aerobic base
  - VO2 work
  - threshold/lactate work
  - anaerobic opt-in
  - flexibility/mobility
  - recovery/readiness
- Beginner users are not auto-prescribed HIIT/SIT.
- SIT is never primary unless user explicitly opts in and eligibility gates pass.
- HR-zone prescriptions expose whether HRmax is tested or estimated.
- Stretching copy claims ROM/flexibility benefits, not broad injury prevention.
- Recovery copy never diagnoses overtraining.
- `docs/CITATIONS.md` and `CitationRegistry.all` are consistent.

## Suggested PR Breakdown

1. `fix/science-citation-metadata-and-policies`
2. `feat/coach-system-load-facts`
3. `feat/coach-evidence-typed-claims`
4. `feat/coach-multisystem-recommendations`
5. `feat/coach-system-aware-decision-scoring`
6. `feat/coach-why-today-evidence-ui`
7. `docs/coach-evidence-maintenance`

Keep each PR shippable and testable. Do not merge a PR that adds a coaching claim without the citation integrity tests passing.

