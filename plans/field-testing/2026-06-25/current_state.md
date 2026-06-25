# Coach Evidence Upgrade — current state

Tracks the phased rollout of `coach-expert-system-evidence-upgrade-plan.md`.

## Phase 1 — Citation QA & guardrails ✅ (branch `fix/science-citation-metadata-and-policies`)

Shipped:

- **Metadata fixes** in `CitationRegistry`: `wingateTest` DOI (`…00001`),
  `pellandDoseResponse2026` (authors/title), `crowleyVO2Intensity2022`
  (Translational Sports Medicine + title), `poonHIIT2024` (Scand J Med Sci Sports +
  title/DOI), `sawMonitoring2016` (BJSM systematic review).
- **11 new citations**: `zourdosRIR2016`, `tanakaMaxHR2001`, `kaufmannThreshold2023`,
  `milanovicHIIT2015`, `slothSIT2013`, `buchheitLaursenHIIT2013`, `konradStretchROM2024`,
  `behmStretching2016`, `lauersenInjuryPrevention2014`, `fieldFitnessReliability2022`,
  `tongPlank2014` (all PubMed-verified).
- **Typed claim system**: `EvidenceClaimCategory` (14 cases) + claim-specific pools
  (`activityMinutesHealthPool`, `stepsHealthPool`, `aerobicBasePool`, `vo2TrainingPool`,
  `thresholdTrainingPool`, `anaerobicTrainingPool`, `strengthFrequencyPool`,
  `strengthVolumePool`, `strengthIntensityPool`, `periodizationPool`, `flexibilityROMPool`,
  `recoveryMonitoringPool`, `concurrentTrainingPool`, `fieldTestValidityPool`) +
  `CitationRegistry.citationPool(for:)`. Legacy `aerobicPool`/`recoveryLoadPool` kept for
  back-compat (UI migration is Phase 5). `EvidenceClaim` gained an optional typed
  `category` + a category-based initializer.
- **Assessment evidence policy**: `AssessmentEvidencePolicy` (validated / fieldEstimate /
  personalBenchmark) + `AssessmentKind.evidencePolicy`; `citationIds` now derives from it.
  Bodyweight tests (push-up/pull-up/squat/hollow) are explicit personal benchmarks; plank
  cites Tong 2014; manual VO₂ is low-confidence.
- `recovery.stretch` candidate now cites ROM science.
- **Integrity tests** (CitationIntegrityTests): unique IDs, resolvable URLs, corrected
  metadata, every pool/category resolves, no cross-category leakage, every AssessmentKind
  has a policy, every candidate is cited (unless rest/empty), every decision
  reason/warning ID resolves.
- `docs/CITATIONS.md`: new entries, corrected entries, Claim-classes table, assessment
  policy section.

Verification: `swift test` = 366 pass (incl. CitationIntegrityTests 17, ScienceCopyTests
5, AssessmentMathTests 13); iOS app `xcodebuild … build` = BUILD SUCCEEDED.

Intentionally deferred to later phases:

- Migrating `WhyThisTodayView` off `aerobicPool`/raw `poolId` to typed categories → Phase 5.
- New recommendation rules / system-aware scoring → Phases 3–4.

## Phase 2 — Multi-system facts ✅ (branch `feat/coach-system-load-facts`)

Shipped (additive — decision engine behavior unchanged):

- New `SystemLoad.swift`: `TrainingSystem` (9), `AerobicIntensityBucket`, `SystemLoad`,
  `ReadinessSnapshot` (+ `from(ReadinessEntry)`), `AssessmentCoverage`, `LoadSpikeFlag`,
  `CardioZoneSource`, plus `TrainingEvent.systemExposures` event→system classification
  and `SystemLoadComputer` (loads, aerobicMinutesByBucket, loadSpikeFlags, zoneSource,
  assessmentCoverage).
- `CoachFacts`: added `systemLoads`, `readiness`, `assessmentCoverage`, `loadSpikeFlags`,
  `zoneSource`, `aerobicMinutesByBucket`, a `staleSystems` helper, and an explicit
  initializer (new fields defaulted). `make` gained optional `assessments` +
  `readinessEntry` params and computes the new facts.
- `TrainingFacts`: added `repeatedDeclineByExercise`, `sessionsSinceDeloadByExercise`,
  `volumeTrendByPart` (computed in `make`).
- Tests: 7 new CoachFactsTests (classification, aggregation/staleness, readiness, coverage,
  zone source) + 3 new TrainingFactsTests (volume trend, repeated decline, sessions since
  deload).

Verification: `swift test` = 376 pass; iOS `xcodebuild … build` = BUILD SUCCEEDED.

Deferred: wiring the app's readiness/assessment data into `CoachFacts.make` happens when
it's consumed (Phase 4/5); for now those fields default empty in production.
## Phase 3 — Recommendation rules ✅ (branch `feat/coach-multisystem-recommendations`)

Shipped (additive — rules produced but not yet consumed by the decision engine):

- `RecommendationKind` +10 cases (strengthBlock, volumeAdjust, periodizedVariation,
  aerobicBase, vo2Intervals, thresholdTempo, anaerobicOptIn, flexibility,
  recoveryReadiness, assessmentPrompt).
- `Recommendation` gains optional `system`, `evidenceCategory`, `whyNowFacts`,
  `riskNotes`, `uncertainty`, `minimumEligibility`.
- New `CoachRuleSupport.swift` → `CoachRecommendationEngine.run(_:anaerobicOptIn:)`
  implementing C1–C9 over `CoachFacts`: strength block (periodization), volume
  personalization (add below MEV / hold-reduce over MRV + poor readiness), aerobic
  base, VO₂ intervals (beginners excluded; base + no collision required), threshold
  (low-confidence when HRmax age-estimated; never mortality cites), anaerobic opt-in
  (advanced/explicit only, never auto-primary, risk notes), flexibility (ROM only),
  recovery/readiness (no overtraining diagnosis), assessment prompts. Each rule cites
  only its claim category's pool.
- 11 new RecommendationEngineTests covering goal-specific block, volume+frequency
  citation split, aerobic-base copy, VO₂ eligibility/citations, threshold confidence,
  anaerobic opt-in gating, flexibility copy, recovery copy, assessment prompts.

Verification: `swift test` = 387 pass; iOS `xcodebuild … build` = BUILD SUCCEEDED.

Deferred: wiring these into candidates/scoring + UI → Phases 4–5.
## Phase 4 — Decision scoring & candidates ⏳
## Phase 5 — UI handoff ⏳
## Phase 6 — Docs & final verification ⏳
