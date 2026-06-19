# 04 — Periodic Assessments + HIIT as prescribed training

## Problem / why
A coach measures. We add **standardized, repeatable tests** the engine schedules,
tracks longitudinally, and re-tests — **pre/post like a research study** — then makes
**non-medical coaching** recommendations from the deltas. HIIT stops being a free-
standing timer and becomes **prescribed cardio driven by the user's VO₂max / anaerobic
results**, closing the train→test→adjust loop.

## Assessment battery (all opt-in, all "coaching, not medical")
### Strength
- **e1RM / rep-max test**: a top single or an AMRAP at a fixed %; estimate 1RM via
  Epley/Brzycki (we already compute e1RM). Track per main lift over time.
- **Standardized protocol**: warm-up ramp the app guides; record the test set distinct
  from normal sets so trends aren't polluted.

### Strength-endurance
- **Max reps bodyweight** (push-ups, pull-ups, bodyweight squat), **plank/hollow time**.
  Simple, equipment-free, repeatable; good "before/after" signal for beginners.

### Aerobic (VO₂max estimate)
- **Field tests with validated equations**: Cooper 12-minute run distance, or
  **Rockport 1-mile walk + ending HR** (uses HR strap we already support), or a submax
  step test. Output an **estimated VO₂max range** (not a medical number).
- *Honesty*: present as an estimate + trend; emphasize change over absolute value.

### Anaerobic power
- **Wingate (30-s all-out)** on an **FTMS** bike/erg (we already have FTMS BLE):
  capture peak power, mean power, **fatigue index**. Gate on FTMS hardware; offer a
  bodyweight fallback (e.g. 30-s max effort) where no machine exists.

## Pre/post study framing
1. **Baseline**: engine prompts a relevant test when starting a focus block.
2. **Train**: the engine prescribes the block (volume/intensity for lifting; HIIT
   protocol for cardio/anaerobic).
3. **Re-test** at block end (default 6–8 wks, D5): engine computes the **delta**,
   reports it with context ("+0.4 est-VO₂max points; meta-analytic 8-wk HIIT response
   is …"), and adjusts the next block.
4. Everything stored as `Assessment` rows for a longitudinal chart.

## HIIT integration (HIIT stays; boxing leaves)
- Existing protocols (`gibala`, `sit`, `rehit`, `tenTwentyThirty`, Norwegian 4×4) become
  **engine-prescribed** by result:
  - Low estimated VO₂max / aerobic goal → prescribe **4×4 / long-interval** blocks;
    re-test VO₂max.
  - Anaerobic/power goal or low Wingate mean-power → prescribe **SIT/Wingate-style**
    repeats; re-test Wingate.
- The engine cites the HIIT protocol's evidence (e.g. SIT/Gibala, RHIIT, 10-20-30,
  Norwegian 4×4) the same way lifting rules cite theirs.

## Data-model deltas (additive)
- New `Assessment` `@Model`: `{ id, date, kind (enum: e1RM, repMax, pushupMax,
  pullupMax, plankTime, vo2maxField, wingate), value(s), protocol, lift?, notes,
  updatedAt }`. Optional/defaulted; CloudKit-safe.
- VO₂max/Wingate store their raw inputs (distance/HR/power series) so estimates can be
  recomputed if equations improve.
- HIIT prescription links an `IntervalPlan` to a goal + the assessment that triggered it.

## Engine rules added (cite each)
- VO₂max estimation equations (Cooper / Rockport / ACSM submax). *Cite source equations.*
- Wingate metrics + interpretation (peak/mean/fatigue index norms). *Cite Wingate
  literature.*
- HIIT dose-response (interval format → aerobic/anaerobic adaptation). *Cite SIT/HIIT
  meta-analyses + named protocols.*
- "Re-test cadence" + minimal-detectable-change guardrails so noise isn't read as
  progress.

## Testing
- Estimation math is pure → `swift test` (Cooper/Rockport→VO₂max; Wingate peak/mean/
  fatigue from a power series; e1RM already tested).
- Assessment persistence + longitudinal delta computation.
- Engine: a low-VO₂max baseline produces a cited 4×4 prescription; a re-test with
  improvement advances the block.

## Open
- D5 assessment cadence (app-suggested vs user-driven; default opt-in).
- Which field VO₂max equation(s) to ship first (recommend Rockport walk — uses our HR
  strap, low-risk for general users — + Cooper for runners).
- Wingate UX without a smart trainer: offer the protocol but mark power-based metrics
  "needs FTMS"; bodyweight anaerobic fallback otherwise.
