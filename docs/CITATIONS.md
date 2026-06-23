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
<https://doi.org/10.2165/00007256-198704060-00005>

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
ACSM (2021). *ACSM's Guidelines for Exercise Testing and Prescription (11th ed.).*
**Wolters Kluwer.**
<https://www.acsm.org/education-resources/books/guidelines-exercise-testing-prescription>

- **Used by:** the 1.5-mile run VO₂max assessment.
- **What it supports:** standardized field-test protocol for estimating cardiorespiratory
  fitness.

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

### `acsmResistance2026` — ACSM 2026 resistance training guidelines
ACSM (2026). *ACSM Resistance Training Guidelines Update 2026.* **ACSM Position Stand.**
<https://acsm.org/resistance-training-guidelines-update-2026/>

- **Used by:** the cold-start starter prescription, beginner A/B sessions, volume guidance.
- **What it supports:** all major muscle groups at least twice weekly, heavier loads for
  strength, ~10 weekly sets/muscle for hypertrophy as a starting range.
- **App policy vs evidence:** the ~10 set starting range is evidence-backed; individual
  progression from there is a coaching policy.

### `whoPhysicalActivity2020` — WHO physical activity guidelines
WHO (2020). *WHO Guidelines on Physical Activity and Sedentary Behaviour.*
<https://www.who.int/publications/i/item/9789240014886>

- **Used by:** the 150 min/week moderate-equivalent aerobic target, moderate aerobic rule.
- **What it supports:** 150–300 min moderate or 75–150 min vigorous activity per week.

### `pellandDoseResponse2026` — dose-response meta-analysis
Pelland et al. (2026). *Dose-response relationship between weekly resistance training
volume and muscular adaptations.* **Sports Medicine.**
<https://pubmed.ncbi.nlm.nih.gov/41343037/>

- **Used by:** volume guidance, excessive volume warnings.
- **What it supports:** graded dose-response with diminishing returns; frequency more
  useful for volume distribution than as an independent hypertrophy driver.

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
Saw, Main & Gastin (2016). *Monitoring athletes through self-report.*
**J Sports Sci Med.** <https://pubmed.ncbi.nlm.nih.gov/26423706/>

- **Used by:** readiness check-in rationale.
- **What it supports:** subjective fatigue, soreness, sleep, stress, and mood are useful
  monitoring inputs and respond more consistently to load than objective markers.

### `crowleyVO2Intensity2022` — HIIT vs MICT for VO₂max
Crowley et al. (2022). *Effects of high-intensity interval training and
moderate-intensity continuous training on VO₂max.* **Sports Medicine.**
<https://pubmed.ncbi.nlm.nih.gov/38655159/>

- **Used by:** VO₂max interval prescription (replaces hiitVo2max).
- **What it supports:** both HIIT and moderate continuous training improve VO₂max;
  higher intensity has a small-to-moderate advantage.

### `poonHIIT2024` — HIIT umbrella review
Poon et al. (2024). *HIIT versus MICT for cardiorespiratory fitness: An umbrella
review.* **Sports Medicine.** <https://pubmed.ncbi.nlm.nih.gov/38760916/>

- **Used by:** VO₂max interval prescription (secondary citation).
- **What it supports:** HIIT and MICT both effective; choice depends on preference,
  recovery, and baseline fitness.

### `ramosCampoSplit2024` — full-body vs split routines
Ramos-Campo et al. (2024). *Effects of full-body and split routines on strength and
hypertrophy.* **Sports Medicine.** <https://pubmed.ncbi.nlm.nih.gov/38595233/>

- **Used by:** split/full-body template selection.
- **What it supports:** full-body and split routines produce similar results when volume
  is equated; schedule and preference can decide the split.

### `usPhysicalActivity2018` — U.S. physical activity guidelines
HHS (2018). *Physical Activity Guidelines for Americans, 2nd edition.*
<https://health.gov/sites/default/files/2019-09/Physical_Activity_Guidelines_2nd_edition.pdf>

- **Used by:** weekly aerobic target (secondary).

### Corrected existing entries

- `frequencyMeta`: the 2019 meta-analysis found volume-equated frequency does not
  significantly or meaningfully affect hypertrophy. Frequency is useful for
  distributing volume and fitting schedules, not as an independent hypertrophy dose.

- New prescriptive rules must cite published work before shipping — no un-cited
  prescription is allowed past the engine's tests.
