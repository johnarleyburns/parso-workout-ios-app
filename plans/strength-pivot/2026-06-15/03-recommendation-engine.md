# 03 — The Scientific Expert Engine (the core advantage)

## Problem / why
This is the product. A **deterministic, on-device, transparent rule engine** that
turns the user's logged history + test results into **coaching recommendations whose
every output cites the weightlifting science it came from**. Not an LLM, not a cloud
service, not a black box: "**1980s expert-system AI, accelerated by modern
hardware**." Modern silicon lets a forward-chaining rules engine evaluate a user's
entire training history instantly; the value is the *curated, cited knowledge base* —
which, being open-source, is peer-reviewable.

## Why rule-based (not ML/LLM)
- **Privacy/offline/zero-cost**: runs in `CadenceCore`, no data leaves the device, no
  server, no inference bill — matches every core principle.
- **Transparency = the moat**: incumbents are black boxes. We show *the rule and the
  citation* behind each suggestion. Trust is the differentiator.
- **Determinism = testability**: pure Swift, `swift test`-verifiable, reproducible.
- **Honesty**: encodes only published findings; no hallucinated coaching.

## Architecture (CadenceCore, pure)
```
Facts (derived from SwiftData history + tests)
        │
        ▼
  WorkingMemory  ──►  InferenceEngine (forward-chaining)  ──►  [Recommendation]
        ▲                      │
        │                      ▼
   KnowledgeBase  =  [Rule]   (each Rule: id, when(facts)->Bool,
                               then -> Recommendation, citation, confidence)
```
- **`TrainingFacts`** (computed snapshot): per-muscle weekly sets (working sets, last
  1–4 wks), per-lift `e1RM` trend, intensity distribution (%1RM bands), avg RIR/RPE,
  frequency/muscle, days since last session/muscle, staleness/plateau flags, latest
  assessment results, user goal + experience + schedule. Reuses batch-8
  `BodyPart`/muscle index, `PRCalculator`, `WeeklyStats`.
- **`Rule`**: `{ id, rationale, citationKey, priority, matches(TrainingFacts)->Bool,
  produce(TrainingFacts)->Recommendation? }`. Pure, isolated, individually tested.
- **`InferenceEngine.run(facts) -> [Recommendation]`**: forward-chains, resolves
  conflicts by priority + confidence, dedupes, returns a ranked, explained list.
- **`Recommendation`**: `{ kind, target (lift/muscle/session), action, message,
  why (rationale), citation, confidence }`. The UI renders an expandable
  **"the science"** card (D3) with the citation.
- **`Citation` registry**: a bundled list of references (author/year/title/DOI/url) the
  rules point to. Open-source + visible in-app.

## The knowledge base — initial rule set (each cites published work)
> These are the *encoded principles*; exact thresholds live in code as named constants,
> conservative by default, and adjustable as evidence updates.

1. **Volume landmarks (MEV/MAV/MRV).** Compute weekly sets/muscle; compare to bands
   (≈ MEV 6–10, MAV 10–20, MRV 18–30 sets/muscle/wk, experience-scaled). Below MEV →
   "add sets"; in MAV → "hold/progress"; near MRV with rising fatigue → "deload".
   *Cite: dose-response meta-regression on weekly volume (Schoenfeld/Pelland et al.).*
2. **Intensity × goal (per the re-examined repetition continuum).** Encodes
   Schoenfeld, Grgic, Van Every & Plotkin (2021), *Loading Recommendations for Muscle
   Strength, Hypertrophy, and Local Endurance*, **Sports 9(2):32** — the user-supplied
   anchor paper:
   - **Strength** → heavy loads, **1–5 reps @ ~80–100% 1RM** (clear dose-response for
     1RM).
   - **Hypertrophy** → **similar growth across a wide load range (≥~30% 1RM)** *when
     sets are taken to/near failure* — so the engine treats **proximity-to-failure
     (RIR), not load, as the primary hypertrophy driver**; default to a practical
     ~6–15 reps at 0–3 RIR but allow lighter loads if the user trains hard.
   - **Endurance** (D4) → higher reps / lower loads; the paper flags endurance evidence
     as equivocal, so the engine is **conservative + clearly labeled lower-confidence**
     here.
   *Cite: Schoenfeld et al. 2021 (PMC7927075); supporting load/rep-range meta-analyses.*
3. **Frequency.** Recommend ≥2 sessions/muscle/wk when volume is high (splitting
   volume improves quality). *Cite: frequency meta-analyses.*
4. **Proximity to failure / RIR autoregulation.** Use logged RIR/RPE to titrate;
   chronic 0 RIR + stalled e1RM → reduce proximity / deload. *Cite: RIR-based RPE
   autoregulation (Helms et al.).*
5. **Progression (double progression + e1RM).** Within a rep range, add reps to the
   top of range, then add load; set next-session targets from `e1RM` (Epley/Brzycki)
   and RIR. *Cite: progressive overload literature; 1RM-estimation equations.*
6. **Plateau & deload detection.** Stalled/again-declining e1RM over N sessions, or
   rising session RPE at equal load, or volume sustained near MRV → prescribe a deload
   week (reduce volume/intensity). *Cite: fatigue-management/overreaching literature.*
7. **Lagging body-part balance.** Reuse the batch-8 missing-parts logic + push/pull
   balance to suggest exercise additions targeting under-stimulated muscles. *Cite:
   regional/volume-distribution work.*
8. **Periodization scheduling.** Offer block or **daily undulating (DUP)** structuring
   across the week. *Cite: periodization meta-analyses (DUP ≥ non-periodized).*
9. **Recovery/readiness (if captured).** Optional soreness/sleep/HRV (from HealthKit)
   nudges volume up/down. *Cite: monitoring literature.* (Opt-in; non-medical.)

## UX surface
- A **"Coach" tab/home card**: this week's prescription + 1–3 top insights, each with a
  "Why / the science" expander (citation). Pre-fills the next session's targets
  (load/reps/RIR) into the logger.
- **Transparency is mandatory (D3)**: no un-cited prescription ships.
- **Non-medical framing (D6)**: a one-time disclaimer; language is "coaching," never
  diagnosis/therapy.

## Data-model deltas (additive)
- Persist `RIR`/`RPE` already supported on `SetEntry` (good). Add optional
  `goal`, `experienceLevel`, `weeklySchedule` to settings; optional readiness inputs.
- No engine state needs storing — recommendations are recomputed from facts (cheap,
  deterministic). Optionally cache the latest snapshot for the Coach card.

## Testing
- Each rule: table-driven `swift test` with synthetic `TrainingFacts` → expected
  `Recommendation` (incl. boundary cases at MEV/MAV/MRV, plateau windows).
- Engine: golden scenarios (e.g. "8 sets back, flat e1RM, 2 RIR" → "add 2 sets, cites
  volume dose-response"); conflict-resolution determinism; never emits an un-cited rec.
- Property test: recommendations are stable/idempotent for identical facts.

## Open
- D3 transparency-UX confirmation. D4 goals at launch (strength/hypertrophy/both).
- Exact threshold constants + the **citation list** need a focused evidence pass before
  P5 (curate references; conservative defaults; document each in `CITATIONS.md`).
- How much to lean on optional HealthKit readiness (HRV/sleep) vs keep v1 purely
  training-load based (recommend: training-load first, readiness opt-in later).
