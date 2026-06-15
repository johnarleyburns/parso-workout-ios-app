# Cadence → "The science-based, private lifting coach" — strategic pivot

_Date: 2026-06-15. Author: strategy plan per CLAUDE.md dev methodology. This is the
`00-overview` anchor; see the numbered section files for detail. Aggressive by
request._

## The bet (one sentence)
Cadence stops being a broad multi-sport logger and becomes **the open-source,
on-device, zero-subscription strength coach whose recommendations come *only* from
published weightlifting/exercise science** — a transparent "expert engine" that
periodically *tests* the user (like a research study's pre/post) and coaches them to
the next level. Privacy + science-transparency is the moat no subscription incumbent
can copy.

## Why this wins (from the competitive analysis)
- Every serious competitor (Fitbod, Caliber, Future, Juggernaut) is a **subscription
  black-box**. Our differentiator: **every recommendation cites the study/principle
  behind it**, runs **on-device**, and costs nothing. "Own your data, see the
  reasoning" is both a privacy story and a coaching story.
- The biggest functional gap identified was **no programming/progression**. This pivot
  makes that gap the *core product*, not a missing feature.
- Breadth was the risk ("good at everything, best at nothing"). We cut breadth on
  purpose: **strength is the spearhead**; HIIT stays only because it folds into the
  science engine (VO₂max / anaerobic power); **boxing + CrossFit spin out**.

## Non-negotiable principles (unchanged)
Open-source · 100% on-device · zero server / zero account · zero subscription ·
additive-only schema (CloudKit-safe) · logic in `CadenceCore`, `swift test`-verifiable.

## The six strategic moves (→ section files) — decisions LOCKED, see `decisions.md`
1. **Remove CrossFit** (`git tag` the code first, then delete; recoverable for a future
   separate app). **Keep Boxing, reclassified as cardio-only.** HIIT stays (→ engine).
   → `01-spinout-boxing-crossfit.md`
2. **Replace the hand-rolled catalog** with **free-exercise-db** (Unlicense/public-
   domain), **embedding instructions + images + muscles on-device** — ends the EXRX-
   copyright workaround. → `02-exercise-library-cc0.md`
3. **Build the Scientific Expert Engine** — deterministic, on-device, **rule-based
   forward-chaining** coach over a citable KB of lifting science ("1980s AI, modern
   hardware"). **Every recommendation shows an always-visible "why + citation" card**
   (D3). → `03-recommendation-engine.md`
4. **Periodic standardized Assessments** (strength / strength-endurance / aerobic /
   anaerobic), **app-suggested every ~6–8 wks, opt-in** (D5); pre/post like a study.
   HIIT becomes *prescribed* training driven by VO₂max/Wingate. → `04-assessments-and-hiit.md`
5. **Coach-driven Home** — on every launch the coach recommends a session; the user can
   **Do this / Start Workout / Log a Workout** (three-action spine). → `05-coach-driven-home.md`
6. **Goals at launch: Strength + Hypertrophy + Endurance** (D4); reposition + onboarding/
   goal intake around "your private, science-based lifting coach."

## Honest risks (call them now)
- **Scientific credibility is the product** — getting the knowledge base right
  (citations, thresholds, edge cases) is the hard part and the liability surface.
  Mitigation: transparent rules + citations, conservative defaults, **non-medical
  "coaching only" framing**, and a public, reviewable KB (open-source = peer review).
- **Field-test validity**: home VO₂max/1RM estimates are noisy. Mitigation: present
  ranges + trends, not false precision; prefer *change over time* over absolute values.
- **Hardware**: Wingate/anaerobic needs an FTMS machine or bike (we already have FTMS
  BLE). Gate those tests on hardware; offer bodyweight/field fallbacks.
- **Scope**: this is several releases. The roadmap phases it so each ships value alone.
- **CC0 data quality**: free-exercise-db has gaps/dupes; we curate + map to our muscle
  model rather than trust blindly (see `02`).

## Phased roadmap (one branch+PR per phase; stack where dependent)
| Phase | Deliverable | Depends on | Ships value alone? |
|------|-------------|-----------|--------------------|
| **P0** | Strategy + decisions locked (this doc + `decisions.md`) | — | n/a |
| **P1** | **Remove CrossFit** (tag then delete) + **boxing→cardio**; clean, focused app. | — | Yes (focuses the app) |
| **P2** | **CC0 library import**: ingest free-exercise-db → our `ExerciseTemplate` schema, map muscles→`MuscleCatalog`/`BodyPart`, bundle PD images + instructions on-device; retire EXRX links. | — | Yes (richer library, offline images) |
| **P3** | **Engine core (read-only insights) + Coach-Home layout**: `CadenceCore` rules computing weekly per-muscle volume vs MEV/MAV/MRV, e1RM trends, frequency, intensity distribution — surfaced as *cited insights* in the new Coach card + 3-action Home spine (`05`). | P2 | Yes (analytics + new Home) |
| **P4** | **Assessments v1**: strength (e1RM / AMRAP) + strength-endurance tests; baseline→retest tracking; engine reports deltas. | P3 | Yes |
| **P5** | **Prescriptive engine + live Coach card**: next-session/next-week recommendations (load, sets, RIR, deload, exercise swaps) each with rule + citation; "Do this" pre-fills the logger with prescribed targets (`05`). | P3 | Yes (the coach) |
| **P6** | **Cardio/anaerobic assessments + HIIT loop**: VO₂max field test, Wingate via FTMS; prescribe HIIT protocols from results; re-test. | P4,P5 | Yes |
| **P7** | **Reposition**: onboarding, goal intake, "coach" home surface, App Store story. | P5 | Yes |

## Decisions — LOCKED 2026-06-15 (full detail in `decisions.md`)
- **D1** Remove CrossFit (git-tag then delete); keep Boxing as cardio.
- **D2** free-exercise-db (Unlicense) base + **embed PD images/instructions on-device**.
- **D3** Always-visible "why + citation" card on every recommendation (core).
- **D4** Goals: **Strength + Hypertrophy + Endurance**.
- **D5** Assessments: app-suggested at block end (~6–8 wks), opt-in.
- **D6** Strictly non-medical "coaching" framing (assumed yes — flag if not).
- **D7** No boxing spin-out; CrossFit preserved via git tag for a future app.
- **D8** Embed + downscale images (on-demand pack if size requires).
- **D9** Curated open `CITATIONS.md`, reviewed before P5.

**Anchor evidence so far:** Schoenfeld, Grgic, Van Every & Plotkin (2021), *Loading
Recommendations for Muscle Strength, Hypertrophy, and Local Endurance* (Sports 9(2):32,
PMC7927075) — drives the intensity×goal rule (`03`). A full `CITATIONS.md` pass precedes P5.
