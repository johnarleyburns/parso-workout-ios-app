# CITATIONS — the evidence behind the coach

Cadence's coaching engine is a deterministic, on-device rule system. **Every insight
and every prescription it produces cites the published work it came from** (strength-
pivot decision **D3**). This file is the curated, human-readable companion to the
in-app reference list (`CitationRegistry` in `CadenceCore/Sources/CadenceCore/Citation.swift`);
the code is the source of truth, this file explains how each reference is *used* and
the standing caveats. Curating it is the **D9** gate that precedes the prescriptive
phase (P5).

Framing is strictly **non-medical coaching** (D6): conservative defaults, change-over-
time over false precision, and lower-confidence labels where the evidence is equivocal.
This is an open, reviewable knowledge base — corrections via PR are welcome.

## References

### `schoenfeld2021` — the load/rep continuum
Schoenfeld, Grgic, Van Every & Plotkin (2021). *Loading Recommendations for Muscle
Strength, Hypertrophy, and Local Endurance: A Re-Examination of the Repetition
Continuum.* **Sports 9(2):32.** <https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7927075/>

- **Used by:** the intensity×goal insight and the **per-goal rep ranges / target RIR**
  the prescriptive engine programs to (`TrainingGoal.repRange` / `targetRIR`).
- **What it supports:** strength favours heavy loads at low reps (~1–5 @ ~80–100% 1RM);
  hypertrophy is similar across a wide load range *when sets are taken near failure*, so
  the engine treats proximity-to-failure (RIR), not load, as the primary hypertrophy
  driver; local-endurance evidence is **equivocal** — endurance prescriptions are
  conservative and flagged lower-confidence.

### `volumeDoseResponse` — weekly volume landmarks
Schoenfeld, Ogborn & Krieger (2017). *Dose-response relationship between weekly
resistance training volume and increases in muscle mass.* **J Sports Sci 35(11).**
<https://doi.org/10.1080/02640414.2016.1210197>

- **Used by:** the MEV/MAV/MRV volume landmarks (`VolumeLandmarks`), the volume insight,
  and the prescriptive **add-volume** rule (sets to add to reach the minimum effective
  range).
- **Caveat:** the MEV/MAV/MRV bands are practical training heuristics scaled by
  experience, not values read directly from one trial; treated as conservative defaults.

### `frequencyMeta` — training frequency
Schoenfeld, Grgic & Krieger (2019). *How many times per week should a muscle be trained
to maximize muscle hypertrophy?* **J Sports Sci 37(11).**
<https://doi.org/10.1080/02640414.2018.1555906>

- **Used by:** the frequency insight (split high weekly volume across ≥2 sessions).

### `oneRMEstimation` — estimated-1RM validity
LeSuer, McCormick, Mayhew, Wasserman & Arnold (1997). *The Accuracy of Prediction
Equations for Estimating 1-RM Performance in the Bench Press, Squat, and Deadlift.*
**J Strength Cond Res 11(4).**
<https://journals.lww.com/nsca-jscr/abstract/1997/11000/the_accuracy_of_prediction_equations_for.1.aspx>

- **Used by:** the strength-assessment insights and the e1RM-based progression targets.
- **Caveat:** estimated 1RM (Epley/Brzycki) drifts at higher rep counts; the engine
  prefers low-rep estimates and emphasises change over time, not absolute precision.

### `rpeAutoregulation` — RIR-based autoregulation _(new in P5)_
Helms, Cronin, Storey & Zourdos (2016). *Application of the Repetitions in Reserve-Based
Rating of Perceived Exertion Scale for Resistance Training.* **Strength Cond J 38(4).**
<https://journals.lww.com/nsca-scj/fulltext/2016/08000/application_of_the_repetitions_in_reserve_based.10.aspx>

- **Used by:** the prescriptive **progression** rule (double progression toward a target
   RIR — add reps to the top of the range, then add load) and the **deload** rule (a
   declining estimated-1RM trend → a lighter, lower-volume week, then re-test).

### `cooperVo2max` — field VO₂max test validity
Cooper (1968). *A means of assessing maximal oxygen intake: Correlation between field
and treadmill testing.* **JAMA 203(3).**
<https://doi.org/10.1001/jama.1968.03140030033008>

- **Used by:** the cardio assessment progress insight for VO₂max (P6).

### `wingateTest` — Wingate anaerobic test
Bar-Or (1987). *The Wingate anaerobic test: An update on methodology, reliability and
validity.* **Sports Medicine 4(6).**
<https://doi.org/10.2165/00007256-198704060-00001>

- **Used by:** the cardio assessment progress insight for the Wingate test, and the
  **SIT prescription** rule (declining Wingate peak power → sprint intervals, P6).

### `hiitVo2max` — HIIT and VO₂max improvement
Helgerud, Hoydal, Wang, Karlsen, Berg, Bjerkaas, Simonsen, Helgesen, Hjorth, Bach &
Hoff (2007). *Aerobic high-intensity intervals improve VO₂max more than moderate
training.* **Medicine & Science in Sports & Exercise 39(4).**
<https://doi.org/10.1249/mss.0b013e3180304570>

- **Used by:** the **cardioHIIT prescription** rule (declining VO₂max → Norwegian 4×4
  intervals, P6).

## Maintenance

- A citation key is only added here once a rule actually points at it; an unused
  reference is removed. `CitationRegistry.all` and this file should list the same set.

### `run1_5mile` — 1.5-mile run test
The 1.5-mile run assessment now cites **`cooperVo2max`** (Cooper 1968), which
validated the original Cooper 12-minute run / 1.5-mile field test against treadmill
VO₂max.

### `rockportWalk` — Rockport 1-mile walk test
Kline et al. (1987). *Estimation of VO₂max from a one-mile track walk, gender, age,
and body weight.* **Med Sci Sports Exerc 19(3).**
<https://doi.org/10.1249/00005768-198706000-00013>

- **Used by:** the Rockport walk VO₂max assessment.
- **What it supports:** submaximal field test that estimates VO₂max from walk time, heart
  rate, age, sex, and body weight.

### `queensCollegeStep` — Queens College step test
McArdle et al. (1972). *Reliability and interrelationships between maximal oxygen
intake, physical work capacity and step-test scores in college women.*
**Med Sci Sports 4(4).** <https://doi.org/10.1249/00005768-197200440-00019>

- **Used by:** the Queens College step-test VO₂max assessment.
- **What it supports:** submaximal step-test protocol for estimating VO₂max from recovery
  heart rate.

### `krieger2010` — single vs multiple sets
Krieger (2010). *Single vs. Multiple Sets of Resistance Exercise for Muscle Hypertrophy:
A Meta-Analysis.* **J Strength Cond Res 24(4).**
<https://doi.org/10.1519/JSC.0b013e3181d4d436>

- **Used by:** routine program citations. Informs the multi-set default for built-in
  programs.
- **What it supports:** multiple sets produce greater hypertrophy than single-set training.

### `rheaPeriodization` — periodized vs non-periodized
Rhea & Alderman (2004). *A Meta-Analysis of Periodized Versus Nonperiodized Strength
and Power Training Programs.* **Res Q Exerc Sport 75(4).**
<https://doi.org/10.1080/02701367.2004.10609174>

- **Used by:** routine program citations. Informs periodized program templates.
- **What it supports:** periodized programs produce greater strength and power gains than
  non-periodized programs.

### `calatayudBodyweight` — bodyweight vs bench press
Calatayud et al. (2015). *Bench Press and Push-Up at Comparable Levels of Muscle
Activity Results in Similar Strength Gains.* **J Strength Cond Res 29(1).**
<https://doi.org/10.1519/JSC.0000000000000589>

- **Used by:** calisthenics routine citations.
- **What it supports:** push-ups and bench press produce similar strength gains when
  matched for effort.

### `channellOlympic` — Olympic lifting
Channell & Barfield (2008). *Effect of Olympic and Traditional Resistance Training on
Vertical Jump Improvement in High School Boys.* **J Strength Cond Res 22(5).**
<https://doi.org/10.1519/JSC.0b013e318181a3d0>

- **Used by:** Olympic lifting routine citations.
- **What it supports:** Olympic-style training improves explosive power (vertical jump).

### `zourdosDUP` — daily undulating periodization
Zourdos et al. (2016). *Modified Daily Undulating Periodization Model Produces Greater
Performance Than a Traditional Configuration in Powerlifters.*
**J Strength Cond Res 30(3).** <https://doi.org/10.1519/JSC.0000000000001165>

- **Used by:** DUP program citations.
- **What it supports:** daily undulating periodization can outperform traditional
  periodization for strength.

### `amirthalingamGVT` — German Volume Training
Amirthalingam et al. (2017). *Effects of a Modified German Volume Training Program on
Muscular Hypertrophy and Strength.* **J Strength Cond Res 31(11).**
<https://doi.org/10.1519/JSC.0000000000001747>

- **Used by:** excessive per-session volume warnings.
- **What it supports:** found no advantage to 10 sets over 5 per exercise per session.
- **App policy:** GVT is not selected automatically by Coach; it is available only as an
  advanced user-chosen template with this caveat.

### `williamsLinearPeriodization` — linear periodization
Williams et al. (2017). *Comparison of Periodized and Non-Periodized Resistance Training
on Maximal Strength: A Meta-Analysis.* **Sports Med 47(10).**
<https://doi.org/10.1007/s40279-017-0734-y>

- **Used by:** linear periodization program citations (5/3/1, nSuns).
- **What it supports:** periodized resistance training is more effective for maximal
  strength than non-periodized training.

### `tufanoCluster` — cluster sets
Tufano, Brown & Haff (2017). *Theoretical and Practical Aspects of Different Cluster Set
Structures: A Systematic Review.* **J Strength Cond Res 31(3).**
<https://doi.org/10.1519/JSC.0000000000001581>

- **Used by:** cluster-set program citations.
- **What it supports:** cluster sets allow higher-quality repetitions at heavier loads by
  introducing intra-set rest.

## Recovery-aware redesign citations (2026-06-22)

### `ekelundActivityMortality2016` — physical activity dose-response meta-analysis
Ekelund et al. (2016). *Does physical activity attenuate, or even eliminate, the
detrimental association of sitting time with mortality?* **The Lancet 388(10051).**
<https://doi.org/10.1016/S0140-6736(16)30370-1>

- **Used by:** the 150 min/week moderate-equivalent aerobic target, moderate aerobic
  rule, aerobic session candidates.
- **What it supports:** a harmonised meta-analysis of over 1 million adults found a
  graded dose-response between physical activity volume and reduced all-cause mortality;
  ~60–75 min/day of moderate activity eliminated the excess risk of prolonged sitting.
- **Replaces:** `whoPhysicalActivity2020` (WHO guidelines — removed as appeal to
  authority) and `usPhysicalActivity2018` (HHS guidelines — removed).

### `pellandDoseResponse2026` — dose-response meta-regression
Pelland, Remmert, Robinson, Hinson & Zourdos (2026). *The Resistance Training Dose
Response: Meta-Regressions Exploring the Effects of Weekly Volume and Frequency on
Muscle Hypertrophy and Strength Gains.* **Sports Medicine.**
<https://doi.org/10.1007/s40279-025-02344-w>

- **Used by:** `strengthVolumePool` — volume guidance, excessive volume warnings.
- **What it supports:** graded dose-response with diminishing returns; frequency more
  useful for volume distribution than as an independent hypertrophy driver.
- **Metadata corrected (2026-06-25):** authors and title updated to match PMID 41343037.

### `parejaBlancoRecovery2020` — recovery after training to failure
Pareja-Blanco et al. (2020). *Recovery of neuromuscular performance after resistance
training to failure.* **European Journal of Applied Physiology.**
<https://pubmed.ncbi.nlm.nih.gov/30036284/>

- **Used by:** recovery gates, high-fatigue 72h deferral.
- **What it supports:** neuromuscular decrements up to 48h after failure protocols.
- **App policy:** the 48h/72h gates are conservative product policy informed by this
  study; they are not claims that every person recovers in exactly 48h.

### `schumannConcurrent2022` — concurrent training compatibility
Schumann et al. (2022). *Compatibility of concurrent aerobic and strength training.*
**Sports Medicine.** <https://pmc.ncbi.nlm.nih.gov/articles/PMC8891239/>

- **Used by:** lower-body collision gate (hard cardio after strength).
- **What it supports:** concurrent training generally does not compromise strength or
  hypertrophy; explosive-strength may be attenuated when same-session.

### `meeusenOvertraining2013` — overtraining consensus
Meeusen et al. (2013). *Prevention, diagnosis and treatment of the overtraining
syndrome: ECSS/ACSM consensus.* **MSSE.**
<https://pubmed.ncbi.nlm.nih.gov/23247672/>

- **Used by:** pain/illness safety gate, consecutive hard-day warnings.
- **What it supports:** overtraining syndrome cannot be diagnosed by simple app markers;
  Coach flags persistent poor recovery and suggests reducing load.
- **App policy:** Coach never labels a user "overtrained."

### `sawMonitoring2016` — self-report monitoring
Saw, Main & Gastin (2016). *Monitoring the athlete training response: subjective
self-reported measures trump commonly used objective measures: a systematic review.*
**Br J Sports Med 50(5).** <https://pmc.ncbi.nlm.nih.gov/articles/PMC4789708/>

- **Used by:** readiness check-in rationale; `recoveryMonitoringPool` (recovery claims).
- **What it supports:** subjective fatigue, soreness, sleep, stress, and mood are useful
  monitoring inputs and respond more consistently to load than objective markers.
- **Metadata corrected (2026-06-25):** PMID 26423706 is the BJSM systematic review, not
  the earlier "factors influencing implementation" paper previously recorded.

### `crowleyVO2Intensity2022` — exercise intensity and VO₂max
Crowley, Powell, Bottoms & Sykes (2022). *The Effect of Exercise Training Intensity on
VO₂max in Healthy Adults: An Overview of Systematic Reviews and Meta-Analyses.*
**Translational Sports Medicine.** <https://pmc.ncbi.nlm.nih.gov/articles/PMC11022784/>

- **Used by:** `vo2TrainingPool` — VO₂-interval prescription claims.
- **What it supports:** higher-intensity training has a small-to-moderate advantage for
  VO₂max improvement vs moderate continuous training.
- **Metadata corrected (2026-06-25):** journal is *Translational Sports Medicine*; title
  and authors updated to match PMID 38655159.

### `poonHIIT2024` — HIIT umbrella review
Poon, Sheridan, Chung, Wong & Sun (2024). *High-intensity interval training and
cardiorespiratory fitness in adults: An umbrella review of systematic reviews and
meta-analyses.* **Scand J Med Sci Sports 34(5).** <https://doi.org/10.1111/sms.14652>

- **Used by:** `vo2TrainingPool` — VO₂-interval prescription (secondary citation).
- **What it supports:** HIIT and MICT both effective; choice depends on preference,
  recovery, and baseline fitness.
- **Metadata corrected (2026-06-25):** journal is *Scand J Med Sci Sports*; title/authors
  updated to match PMID 38760916.

### `ramosCampoSplit2024` — full-body vs split routines
Ramos-Campo et al. (2024). *Effects of full-body and split routines on strength and
hypertrophy.* **Sports Medicine.** <https://pubmed.ncbi.nlm.nih.gov/38595233/>

- **Used by:** split/full-body template selection.
- **What it supports:** full-body and split routines produce similar results when volume
  is equated; schedule and preference can decide the split.

## Coach expert-system rewrite — plan adherence & citation pool refs (2026-06-24)

### `mooreLeisureActivity2012` — leisure-time activity pooled cohort
Moore et al. (2012). *Leisure time physical activity of moderate to vigorous intensity
and mortality: a large pooled cohort analysis.* **PLOS Medicine 9(11).**
<https://journals.plos.org/plosmedicine/article?id=10.1371/journal.pmed.1001335>

- **Used by:** aerobic citation pool — one of several interchangeable references for
  aerobic/moderate-equivalent-minute claims shown in the "Why this today" view.
- **What it supports:** pooled analysis of 6 prospective cohorts (654,827 individuals)
  found a dose-response across the activity continuum; ~150 min/week of moderate activity
  was associated with ~1.8 years of added life expectancy.

### `aremDoseResponse2015` — activity dose-response pooled analysis
Arem et al. (2015). *Leisure time physical activity and mortality: a detailed pooled
analysis of the dose-response relationship.* **JAMA Internal Medicine 175(6).**
<https://jamanetwork.com/journals/jamainternalmedicine/fullarticle/2212267>

- **Used by:** aerobic citation pool — interchangeable with other pool refs.
- **What it supports:** pooled analysis of 661,137 individuals from 6 cohorts confirmed
  a curvilinear dose-response; meeting ~150 min/week of moderate activity was associated
  with 31% lower mortality risk, with diminishing returns beyond ~3× the minimum.

### `saintMauriceSteps2020` — step volume and step intensity
Saint-Maurice et al. (2020). *Association of daily step count and step intensity with
mortality among US adults.* **JAMA 323(12).**
<https://doi.org/10.1001/jama.2020.1382>

- **Used by:** aerobic citation pool — interchangeable with other pool refs.
- **What it supports:** higher daily step counts (up to ~8,000–10,000 steps) were
  associated with lower all-cause mortality; step intensity (cadence) added modest
  independent benefit beyond volume.

### `leeAccelerometer2019` — step volume and intensity in older women
Lee et al. (2019). *Association of step volume and intensity with all-cause mortality in
older women.* **JAMA Internal Medicine 179(8).**
<https://doi.org/10.1001/jamainternmed.2019.0899>

- **Used by:** aerobic citation pool — interchangeable with other pool refs.
- **What it supports:** ~4,400 steps/day was associated with significantly lower mortality
  compared to ~2,700 steps/day; benefit plateaued around 7,500 steps/day.

### `halsonRecovery2014` — monitoring training load and fatigue
Halson (2014). *Monitoring training load to understand fatigue in athletes.*
**Sports Medicine 44(Suppl 2).** <https://doi.org/10.1007/s40279-014-0253-z>

- **Used by:** recovery/load citation pool — interchangeable with other pool refs shown
  in recovery-related coach claims.
- **What it supports:** multiple monitoring tools (RPE, wellness questionnaires, HRV,
  biochemical markers) can detect accumulated fatigue; subjective measures are often more
  sensitive to load changes than objective ones.

### `drewFinchInjury2016` — training load and injury/illness
Drew & Finch (2016). *The relationship between training load and injury, illness and
soreness: a systematic and literature review.* **Sports Medicine 46(6).**
<https://link.springer.com/article/10.1007/s40279-015-0459-8>

- **Used by:** recovery/load citation pool — interchangeable with other pool refs.
- **What it supports:** rapid increases in training load (spikes) are associated with
  increased injury risk; monitoring load and managing progression reduces risk.

### `dupuyFatigue2018` — evidence-based recovery techniques
Dupuy et al. (2018). *An evidence-based approach for choosing post-exercise recovery
techniques to reduce markers of muscle damage, soreness, fatigue, and inflammation.*
**Frontiers in Physiology 9.** <https://doi.org/10.3389/fphys.2018.00403>

- **Used by:** recovery/load citation pool — interchangeable with other pool refs.
- **What it supports:** massage was most effective for DOMS and perceived fatigue;
  active recovery, compression, and cold-water immersion had modest effects.
  Recovery strategies should be chosen based on context and individual preference.

### Corrected existing entries

- `frequencyMeta`: the 2019 meta-analysis found volume-equated frequency does not
  significantly or meaningfully affect hypertrophy. Frequency is useful for
  distributing volume and fitting schedules, not as an independent hypertrophy dose.

- New prescriptive rules must cite published work before shipping — no un-cited
  prescription is allowed past the engine's tests.

## Coach evidence upgrade — multi-system citations (2026-06-25)

These references were added to cover the systems Coach now reasons about (strength
intensity/periodization, VO₂, threshold, anaerobic opt-in, flexibility/ROM, and
assessment validity) so each claim cites work that actually supports *that* claim.

### `zourdosRIR2016` — RIR-anchored RPE scale validation
Zourdos et al. (2016). *Novel Resistance Training-Specific Rating of Perceived Exertion
Scale Measuring Repetitions in Reserve.* **J Strength Cond Res 30(1).**
<https://doi.org/10.1519/JSC.0000000000001049>

- **Used by:** `strengthIntensityPool` — RIR/RPE autoregulation claims.
- **What it supports:** lifters can map perceived exertion to repetitions-in-reserve;
  validates the scale Coach programs to (distinct from `rpeAutoregulation`, the
  application paper).

### `tanakaMaxHR2001` — age-predicted HRmax
Tanaka, Monahan & Seals (2001). *Age-predicted maximal heart rate revisited.*
**J Am Coll Cardiol 37(1).** <https://doi.org/10.1016/s0735-1097(00)01054-8>

- **Used by:** HR-zone uncertainty labelling when max HR is estimated, not tested.
- **What it supports:** 208 − 0.7·age estimates HRmax at a population level with a large
  individual SD (~±10 bpm) — so HR-zone prescriptions built on it are low-confidence.

### `kaufmannThreshold2023` — threshold-method agreement
Kaufmann, Gronwald, Herold & Hoos (2023). *Heart Rate Variability-Derived Thresholds for
Exercise Intensity Prescription in Endurance Sports.* **Sports Med - Open 9(1).**
<https://pmc.ncbi.nlm.nih.gov/articles/PMC10354346/>

- **Used by:** `thresholdTrainingPool` — threshold/lactate prescription + uncertainty.
- **What it supports:** HRV-, ventilatory- and lactate-threshold estimates agree on
  average but with wide individual limits of agreement — so threshold zones are flagged
  lower-confidence unless directly tested.

### `milanovicHIIT2015` — HIIT vs continuous training for VO₂max
Milanović, Sporiš & Weston (2015). *Effectiveness of HIT and Continuous Endurance
Training for VO₂max Improvements.* **Sports Med 45(10).**
<https://doi.org/10.1007/s40279-015-0365-0>

- **Used by:** `vo2TrainingPool` — VO₂-interval prescription.
- **What it supports:** interval training produces meaningful VO₂max gains; supports the
  4×4-style VO₂ session.

### `slothSIT2013` — sprint interval training
Sloth, Sloth, Overgaard & Dalgas (2013). *Effects of sprint interval training on VO₂max
and aerobic exercise performance.* **Scand J Med Sci Sports 23(6).**
<https://doi.org/10.1111/sms.12092>

- **Used by:** `anaerobicTrainingPool` — anaerobic opt-in claims only.
- **App policy:** SIT is **never auto-prescribed**; it is an explicit opt-in lane with
  fatigue/safety caveats.

### `buchheitLaursenHIIT2013` — HIIT programming (Part II)
Buchheit & Laursen (2013). *High-Intensity Interval Training, Solutions to the
Programming Puzzle: Part II.* **Sports Med 43(10).**
<https://doi.org/10.1007/s40279-013-0066-5>

- **Used by:** `anaerobicTrainingPool` — anaerobic energy / neuromuscular load claims.
- **What it supports:** programming variables for short maximal efforts and their high
  neuromuscular cost (basis for the conservative opt-in gates).

### `konradStretchROM2024` — chronic stretching and ROM
Konrad et al. (2024). *Chronic effects of stretching on range of motion.*
**J Sport Health Sci 13(2).** <https://pmc.ncbi.nlm.nih.gov/articles/PMC10980866/>

- **Used by:** `flexibilityROMPool` — flexibility/mobility ROM claims, `recovery.stretch`.
- **What it supports:** regular stretching increases range of motion. Claims are limited
  to ROM/flexibility — **not** broad injury prevention.

### `behmStretching2016` — acute stretching effects
Behm, Blazevich, Kay & McHugh (2016). *Acute effects of muscle stretching on physical
performance, range of motion, and injury incidence.* **Appl Physiol Nutr Metab 41(1).**
<https://doi.org/10.1139/apnm-2015-0235>

- **Used by:** `flexibilityROMPool` — ROM/flexibility and stretch-copy caveats.
- **What it supports:** stretching improves ROM; evidence for static stretching alone
  *preventing injury* is weak — copy must not over-claim.

### `lauersenInjuryPrevention2014` — exercise and injury prevention
Lauersen, Bertelsen & Andersen (2014). *The effectiveness of exercise interventions to
prevent sports injuries.* **Br J Sports Med 48(11).**
<https://doi.org/10.1136/bjsports-2013-092538>

- **Used by:** injury-prevention claims for **strength/proprioceptive warm-up programs
  only** — never to back static stretching alone.
- **What it supports:** strength training and multi-component programs reduce injury risk;
  stretching alone shows no significant protective effect.

### `fieldFitnessReliability2022` — field-test reliability
Cuenca-Garcia et al. (2022). *Reliability of Field-Based Fitness Tests in Adults: A
Systematic Review.* **Sports Med 52(8).** <https://doi.org/10.1007/s40279-021-01635-2>

- **Used by:** `fieldTestValidityPool`; fallback for bodyweight benchmark tests
  (`pushupMax`, `pullupMax`, `bodyweightSquatMax`, `hollowHold`, manual `vo2maxField`).
- **What it supports:** general reliability of field-based adult fitness tests. Used only
  as a *reliability* fallback — **not** a population-validity claim for any single test.

### `tongPlank2014` — plank / core-endurance test
Tong, Wu & Nie (2014). *Sport-specific endurance plank test for evaluation of global core
muscle function.* **Phys Ther Sport 15(1).** <https://doi.org/10.1016/j.ptsp.2013.03.003>

- **Used by:** `fieldTestValidityPool`; the `plankHold` assessment.
- **What it supports:** a validated, reliable plank protocol for global core endurance.

## Claim classes — which citations may back which claims

Coach claims are typed by `EvidenceClaimCategory`; each category resolves to exactly one
citation pool via `CitationRegistry.citationPool(for:)`. A pool curated for one class may
**never** be reused for another (enforced by `CitationIntegrityTests`).

| Claim category | Pool | Citations |
|---|---|---|
| `activityMinutesHealth` | activityMinutesHealthPool | ekelundActivityMortality2016, mooreLeisureActivity2012, aremDoseResponse2015 |
| `stepsHealth` | stepsHealthPool | saintMauriceSteps2020, leeAccelerometer2019 |
| `aerobicBase` | aerobicBasePool | ekelundActivityMortality2016, mooreLeisureActivity2012, aremDoseResponse2015 |
| `strengthFrequency` | strengthFrequencyPool | frequencyMeta |
| `strengthVolume` | strengthVolumePool | volumeDoseResponse, pellandDoseResponse2026 |
| `strengthIntensity` | strengthIntensityPool | schoenfeld2021, zourdosRIR2016, rpeAutoregulation |
| `periodization` | periodizationPool | williamsLinearPeriodization, rheaPeriodization |
| `vo2Training` | vo2TrainingPool | crowleyVO2Intensity2022, poonHIIT2024, milanovicHIIT2015 |
| `thresholdTraining` | thresholdTrainingPool | kaufmannThreshold2023 |
| `anaerobicTraining` | anaerobicTrainingPool | wingateTest, slothSIT2013, buchheitLaursenHIIT2013 |
| `flexibilityROM` | flexibilityROMPool | konradStretchROM2024, behmStretching2016 |
| `recoveryMonitoring` | recoveryMonitoringPool | halsonRecovery2014, sawMonitoring2016, dupuyFatigue2018, meeusenOvertraining2013 |
| `concurrentTraining` | concurrentTrainingPool | schumannConcurrent2022 |
| `fieldTestValidity` | fieldTestValidityPool | oneRMEstimation, cooperVo2max, rockportWalk, queensCollegeStep, wingateTest, tongPlank2014, fieldFitnessReliability2022 |

**Rules:**

- Public-health / mortality studies (Ekelund, Moore, Arem, step studies) back only
  health-floor and aerobic-base claims — never performance prescriptions (VO₂, threshold,
  anaerobic, strength).
- Step-count studies back only `stepsHealth`, never the 150-minute threshold.
- `lauersenInjuryPrevention2014` backs injury-prevention claims for strength/warm-up
  programs only; static-stretch copy uses `flexibilityROM` and may not claim broad injury
  prevention.
- SIT/anaerobic citations only appear with the opt-in lane; never an auto-prescription.

## Assessment evidence policy

Every `AssessmentKind` carries an `AssessmentEvidencePolicy`:

- **validated** — published protocol/equation vs a reference standard (`e1RM`, `repMax`,
  `wingate`).
- **fieldEstimate** — field estimate with explicit uncertainty (`cooper12min`,
  `run1_5mile`, `rockportWalk`, `queensCollegeStep`, `plankHold`; manual `vo2maxField` is
  low-confidence).
- **personalBenchmark** — self-tracked, no population-validity claim, with a caveat string
  the UI must show (`pushupMax`, `pullupMax`, `bodyweightSquatMax`, `hollowHold`).

## Where these are surfaced (decision engine → UI)

The typed categories above are consumed end-to-end, so every coach output the user sees
is tappable science:

- **Candidates** (`CoachSession.candidates`) each carry an `evidenceCategory` and cite
  exactly that category's pool: strength → `strengthIntensity`; easy/moderate aerobic →
  `aerobicBase`; threshold tempo → `thresholdTraining`; VO₂ / anaerobic intervals →
  `vo2Training` / `anaerobicTraining` (anaerobic opt-in only); reduced-load strength →
  `recoveryMonitoring`; recovery/mobility → `flexibilityROM`; assessment prompt →
  `fieldTestValidity`.
- **`CoachDecision.scoreBreakdowns[…].reasons`** are typed `EvidenceClaim`s (e.g. a
  stale-system nudge) carrying their own category + selected citation.
- **UI** renders all of the above via `CitationLink`: `CoachInsightsView` rows,
  `CoachDecisionCardView` warnings, `CoachSchedulePreferencesView` guidance, and each
  `CoachAlternativesView` option. No production UI references the legacy
  `aerobicPool` / `recoveryLoadPool` any longer.
