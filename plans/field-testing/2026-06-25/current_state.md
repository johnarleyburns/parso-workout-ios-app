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
## Phase 4 — Decision scoring & candidates ✅ (branch `feat/coach-phase4-decision-scoring`)

Shipped (additive — every existing decision test preserved):

- `CoachSession` gains `systemsTrained: [TrainingSystem]` + `evidenceCategory:
  EvidenceClaimCategory?` (defaulted). Every base candidate is re-tagged with the
  systems it loads and re-cited to its claim category's pool via a single enrichment
  map — fixing the strength candidate's stray `ekelundActivityMortality2016` mortality
  cite (now `.strengthIntensity`). Aerobic→`.aerobicBase`, VO₂→`.vo2Training`,
  recovery→`.flexibilityROM`, rest→`[.recovery]`/no category.
- **New gated candidates** (all reuse existing `CoachSessionKind` so no exhaustive
  switch churn): `aerobic.thresholdTempo` (moderateAerobic/vigorous, only once aerobic
  base ≥90 mod-eq min, cites threshold pool), `aerobic.anaerobicIntervals`
  (vo2Intervals, **opt-in only** via `candidates(for:anaerobicOptIn:)`),
  `strength.reducedLoad` (surfaced on load spike ≥1.3 or poor readiness),
  `assessment.baseline` (when an actively-trained system has no baseline).
- **`SessionScoreBreakdown`** (base · systemNeed · preference · sameDayPenalty ·
  confidencePenalty · reasons) now drives ranking and is exposed on
  `CoachDecision.scoreBreakdowns`. `systemNeed` is capped at ≤12 and is constant within
  a `CoachSessionKind`, so it breaks near-ties on stale systems without overriding the
  strength/aerobic floors or a user's modality preference. `confidencePenalty` (3/5)
  applies to HR-dependent work (VO₂/threshold/anaerobic) when max-HR is age-estimated.
- **Readiness gate** in `SessionEligibilityPolicy`: a poor readiness check-in defers
  all hard work for ~24h (cites recovery-monitoring); easy/recovery/rest stay eligible.
  SIT/anaerobic stays opt-in-gated at candidate generation.
- `CoachDecisionEngine.run` gains `anaerobicOptIn: Bool = false`, threads breakdowns.
- Tests: 9 new (candidate tagging + category-backed cites, no-mortality strength cite,
  threshold gating, anaerobic opt-in, reduced-load on poor readiness, readiness defers
  hard work, assessment prompt, system-need cap vs floor, breakdown/confidence penalty).

Verification: `swift test` = 396 pass; iOS `xcodebuild … build` = BUILD SUCCEEDED.

Deferred: surfacing breakdown/system/category/confidence in the Coach UI → Phase 5.

## Phase 5 — UI handoff ✅ (branch `feat/coach-phase5-ui-handoff`)

App-side only (no CadenceCore change; `swift test` stays at 396):

- **`WhyThisTodayView.buildWhyThisWonClaims`** migrated off the legacy
  `CitationRegistry.aerobicPool` / `recoveryLoadPool` + raw `poolId` to the typed
  `EvidenceClaim(id:text:category:date:)` initializer — strength-days →
  `.strengthFrequency`, aerobic-minutes → `.activityMinutesHealth`, recovery-load →
  `.recoveryMonitoring`. This removes the **last** legacy-pool usage in the app, so
  every "why this won" claim is now category-pure. The primary's
  `scoreBreakdowns[…].reasons` (already typed+cited) are appended so the system-need
  rationale is shown with its own citation.
- **`CoachDecisionCardView`** warnings now resolve `citationIds` and render a
  `CitationLink(compact:)` under each message — previously the warning text was shown
  with no citation (a cite-everything-rule gap).
- **`WhyThisTodayView` Coach's Pick** now surfaces `CoachSession.systemsTrained`
  ("Targets: …") and, when the primary's breakdown carries a `confidencePenalty`
  (age-estimated HRmax), a cited caveat ("HR zones use an age-estimated max …",
  Tanaka 2001).

Verification: iOS `xcodebuild … build` = BUILD SUCCEEDED; CadenceCore unchanged
(`swift test` = 396).

Deferred (low priority, can fold into Phase 6 or later): per-alternative citations in
`CoachAlternativesView`, weekly-target citations in `YourWeekView`, and making the
`CoachDecisionCardView` `CoachSessionKind` switches exhaustive. Legacy
`aerobicPool`/`recoveryLoadPool` remain in CadenceCore (still covered by
CitationIntegrityTests) but are no longer referenced by any production UI.

## Phase 6 — Docs & final verification ⏳
