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

## Maintenance

- A citation key is only added here once a rule actually points at it; an unused
  reference is removed. `CitationRegistry.all` and this file should list the same set.
- New prescriptive rules must cite published work before shipping (D3) — no un-cited
  prescription is allowed past the engine's tests.
