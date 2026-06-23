# Cladiron Coach: recovery-aware, balanced training redesign

**Status:** implementation handoff  
**Date:** 2026-06-22  
**Scope:** `CadenceCore` recommendation engine, HealthKit ingestion, Coach UI, tests, and science registry  
**North-star behavior:** after a user finishes squats, bench press, and deadlifts, Coach must not offer another hard deadlift session. It should defer the deadlift progression, explain why, and choose an eligible recovery, aerobic, or non-overlapping session within a balanced week.

This document is an instruction set for the coding agent. Implement it in phases and keep each phase testable. Do not reinterpret it as a request to add an LLM: Coach remains deterministic, local, explainable, and cited.

## Required design references

- Exact-copy interactive mockup: [`docs/coach-recovery-aware-mockups.html`](docs/coach-recovery-aware-mockups.html)
- Generated visual direction: [`docs/mockups/coach-recovery-aware-concept.png`](docs/mockups/coach-recovery-aware-concept.png)
- Image-generation prompt and mode: [`docs/mockups/coach-recovery-aware-concept.prompt.md`](docs/mockups/coach-recovery-aware-concept.prompt.md)
- A rendered PNG of the exact-copy mockup should be kept beside the concept image when this handoff is implemented.

The generated concept is visual direction only. Where its text differs from the HTML, the HTML and this document are authoritative.

## 1. Audit: what is wrong now

### P0 — recommendations can be physiologically ineligible

1. `TrainingFacts` has only `daysSinceLastSession`; `LiftSnapshot` has no last-trained timestamp, recent set count, recent RPE, or muscle/pattern recovery state (`TrainingFacts.swift:35-50, 72-84`).
2. `progression` emits a recommendation for every non-declining lift in the current window without asking when that lift was trained (`RecommendationRule.swift:47-104`). A lift completed minutes ago remains a valid candidate.
3. `RecommendationEngine` ranks directly by rule priority and confidence. It has no filter/gate stage between candidate generation and ranking (`RecommendationEngine.swift:13-36`).
4. Starting the Coach card does not start the displayed prescription. `launchPrescription` ignores the selected `Recommendation`, calls `pickRoutine`, and opens whichever preset scores highest (`HomeView.swift:623-630`). A correct card can therefore launch a conflicting routine.
5. `pickRoutine` gives recently used plans a `+20` score and same-program plans `+10`, but never rejects movements that are recovering (`RecommendationEngine.swift:45-105`). This actively favors repeating recent work.

### P0 — Coach does not reason over the whole training load

1. `TrainingFacts.make` accepts strength sessions and assessments only. Home queries cardio but does not pass it into Coach (`HomeView.swift:66-84`).
2. The only cardio prescriptions react to a declining VO₂max/Wingate assessment. A strength-only user with no assessment receives no aerobic recommendation.
3. HealthKit imports every workout into `CardioWorkout`; traditional/functional strength falls through to `.other` (`HealthKitProvider.swift:253-263`, `WorkoutRepository.swift:498-514`). Coach cannot tell that an imported unknown workout was strength work and may count it as cardio later.
4. There is no moderate/vigorous aerobic-equivalent calculation, no rolling weekly aerobic target, no hard/easy classification, and no interaction policy for lower-body strength vs. running/HIIT.

### P1 — several facts are mislabeled or unstable

1. Code comments say “trailing 7 days,” but the window starts at the calendar week boundary (`TrainingFacts.swift:147-158`). On Monday, Sunday disappears from “weekly” facts even though it was one day ago.
2. Prior-period trend windows are also anchored to the calendar week, so trends can change abruptly at midnight Monday and compare partial periods.
3. Any session with sets is included even if `endedAt == nil`; an abandoned/in-progress session can affect Coach.
4. A lift snapshot is the single heaviest loaded set in the window, not the most recent comparable performance. It loses session time, number of hard sets, proximity to failure, and exercise variation.
5. `estimatedVO2max` chooses the maximum latest value across different assessment protocols. Different field tests are not interchangeable enough for “take the maximum” to be a defensible trend.
6. Missing RPE is treated as absence of fatigue information rather than reduced confidence.

### P1 — the science layer overstates what sources support

1. `VolumeLandmarks` exposes fixed MEV/MAV/MRV thresholds by body part and experience (`VolumeLandmarks.swift:3-73`). The cited 2017 volume meta-analysis supports a graded volume–hypertrophy association; it does **not** validate those exact “minimum effective,” “maximum adaptive,” or “maximum recoverable” cutoffs. MRV is person- and context-dependent and is not observable from set count alone.
2. The current text for the 2019 frequency meta-analysis claims ≥2 sessions per muscle produces significantly more hypertrophy. The paper's volume-equated conclusion is that frequency does not significantly or meaningfully affect hypertrophy. Frequency is useful for distributing volume and fitting schedules; it is not a magic independent hypertrophy dose.
3. A one-week e1RM decline is described as accumulated fatigue and triggers a 10% deload. Normal measurement noise, exercise order, sleep, technique, and rep selection can all cause this. A deload needs repeated evidence and/or readiness/performance corroboration.
4. “Every preset has a citation” is not the same as “the exact preset is validated.” Krieger's multiple-set meta-analysis does not validate Cladiron's exact 5×5 program. A periodization review does not validate the displayed 5/3/1 percentages. The GVT study cited by the app found no advantage to 10 sets over 5, so 10×10 should not be a Coach default.
5. “Beginner → Norwegian 4×4” in the existing cardio plan is too aggressive as a generic first aerobic prescription. Start inactive users with tolerable moderate work and progress gradually; reserve HIIT for eligible users who opt in and have an aerobic base/readiness.

### P2 — the interaction encourages “more” instead of “appropriate next”

1. The Coach hero always presents a green “Start workout” CTA, even when rest or recovery is the correct output (`CoachCardView.swift:42-53`).
2. The card shows the winning recommendation but not what was ruled out, the last relevant training exposure, the next eligibility time, or the weekly balance it is optimizing.
3. The cold-start full-body session uses back squat, bench press, and deadlift for three sets each. Full-body training is valid, but this is a high-fatigue beginner default with no horizontal pull and unnecessary squat/hinge density. Use alternating full-body A/B sessions and one low-volume hinge.
4. The app treats “cardio” as a secondary recording mode, although the product promise now includes optimal general fitness and VO₂max.

## 2. Evidence model: what Coach may and may not claim

Use this hierarchy in code comments, in-app copy, and citation detail screens.

### Evidence-backed targets

- Adults should generally accumulate **150–300 min/week moderate aerobic activity, 75–150 min/week vigorous activity, or an equivalent combination**, plus muscle strengthening on **2 or more days/week**. Sources: [WHO 2020 guideline](https://www.who.int/publications/i/item/9789240014886), [U.S. Physical Activity Guidelines, 2nd edition](https://health.gov/sites/default/files/2019-09/Physical_Activity_Guidelines_2nd_edition.pdf).
- The 2026 ACSM resistance-training position stand emphasizes consistency, individualization, all major muscle groups at least twice weekly, heavier loads for strength, and roughly 10 weekly sets per muscle for hypertrophy—not complex programming as a prerequisite. Source: [ACSM 2026 update and position-stand link](https://acsm.org/resistance-training-guidelines-update-2026/).
- Full-body and split routines produce similar strength and hypertrophy when volume is equated; schedule and preference can decide the split. Source: [Ramos-Campo et al. 2024](https://pubmed.ncbi.nlm.nih.gov/38595233/).
- Weekly volume has a positive dose-response with diminishing returns; frequency appears more useful for strength practice and volume distribution than as an independent hypertrophy driver. Source: [Pelland et al. 2026](https://pubmed.ncbi.nlm.nih.gov/41343037/).
- Concurrent aerobic + resistance training generally does not compromise maximal strength or hypertrophy. Explosive-strength adaptation may be attenuated when both occur in the same session; separation by at least 3 hours reduced that signal in subgroup analysis. Source: [Schumann et al. 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC8891239/).
- Both lower/moderate-intensity endurance work and HIIT can improve VO₂max; higher intensity has a small-to-moderate average advantage that depends on interval length, volume, duration, and baseline fitness. Sources: [Crowley et al. overview](https://pubmed.ncbi.nlm.nih.gov/38655159/), [Poon et al. 2024 umbrella review](https://pubmed.ncbi.nlm.nih.gov/38760916/).
- Training to failure and high-repetition failure protocols can delay neuromuscular recovery, with decrements observed up to 48 hours in the cited trial. Source: [Pareja-Blanco et al. 2020](https://pubmed.ncbi.nlm.nih.gov/30036284/).
- Subjective fatigue, soreness, sleep, stress, and mood are useful monitoring inputs and often respond more consistently to load than common objective markers. They are not diagnoses. Source: [Saw et al. 2016](https://pubmed.ncbi.nlm.nih.gov/26423706/).
- Overtraining syndrome cannot be diagnosed by a simple app marker; accepted biomarkers do not reliably diagnose it. Coach may flag persistent poor recovery/performance and suggest reducing load or seeking professional input, but must not label a user “overtrained.” Source: [Meeusen et al. ECSS/ACSM consensus](https://pubmed.ncbi.nlm.nih.gov/23247672/).

### Conservative product policies (label as policies, not physiological facts)

- Never recommend the exact same loaded lift again within 24 hours of completed working sets.
- Default to 48 hours before another **hard** exposure for the same primary muscles/movement pattern after a normal hard session.
- Extend the default to 72 hours when the previous session involved failure/high fatigue and the user reports poor readiness; shorten only for an experienced user with low session load and good readiness.
- Keep high-impact or hard lower-body cardio out of the first 24 hours after hard lower-body strength; easy conversational cardio may remain eligible.
- If imported workout type is unknown but HealthKit says strength training, conservatively protect the whole body from hard strength for 24 hours and ask the user to add details.

These are safe, explainable defaults over uncertain individual recovery kinetics. The UI must say “Coach's conservative recovery window,” not “your muscles require exactly 48 hours.”

## 3. Product model: optimize a week, choose an eligible today

Replace the mental model:

```text
rules → recommendations → sort → top
```

with:

```text
unified training events
  → rolling load + recovery + weekly balance facts
  → generate candidate sessions
  → hard eligibility gates
  → score eligible candidates against the adaptive 7-day plan
  → choose today's session
  → explain observed facts, exclusions, choice, and citations
```

Progression is an attribute of a future lift prescription, not automatically today's session.

## 4. Domain changes in `CadenceCore`

### 4.1 Unified training events

Add `TrainingEvent.swift` as a pure value layer. Do not force strength and cardio SwiftData models into one persistence inheritance tree.

```swift
public struct TrainingEvent: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case strength(details: StrengthEventDetails?)
        case aerobic(AerobicEventDetails)
        case intervals(AerobicEventDetails)
        case unknown
    }

    public let id: UUID
    public let start: Date
    public let end: Date
    public let kind: Kind
    public let source: EventSource
    public let completion: EventCompletion
}
```

`StrengthEventDetails` must retain, per exercise:

- canonical exercise ID/name;
- movement patterns: squat, hinge, horizontal push/pull, vertical push/pull, carry, locomotion, core;
- primary and secondary body parts;
- hard working-set count;
- top set and e1RM;
- mean/max RPE when present;
- `reachedFailure` when explicitly known;
- last working-set completion time.

`AerobicEventDetails` must retain:

- modality and impact (`low`, `moderate`, `high`);
- duration;
- intensity classification and its confidence;
- moderate-equivalent minutes;
- lower-body loading/pattern overlap;
- interval vs. continuous.

Convert existing `WorkoutSession` and `CardioWorkout` arrays into events with pure adapters. Ignore soft-deleted rows. Ignore in-progress sessions for weekly completed volume, but use their performed sets as an active hard block.

### 4.2 Preserve HealthKit workout kind

Change `IngestedWorkout` to preserve the source `HKWorkoutActivityType` in an app-owned enum. At minimum distinguish:

- `traditionalStrength`
- `functionalStrength`
- `running`, `walking`, `cycling`, `swimming`, `rowing`
- `hiit`, `boxing`
- `other`

Do not map strength workouts to `CardioType.other`. Either create a small `ImportedWorkout` SwiftData entity or add a safely migratable `trainingKind` field to the existing imported row. Prefer a separate entity if changing `CardioWorkout` would make “cardio minutes” semantics ambiguous.

Imported strength without movements contributes:

- one strength day;
- duration and session timing;
- a 24-hour conservative unknown-strength recovery block;
- no fabricated per-muscle set counts.

Deduplicate the app's own HealthKit strength writeback by UUID so it does not appear as a second unknown-strength event.

### 4.3 Rolling facts, not calendar-week facts

Replace `weekStart` in Coach facts with exact windows:

- acute/recovery: exact timestamps over 72 hours;
- weekly dose: `now - 7 days ... now`;
- trend: comparable rolling 28-day blocks or session-to-session observations;
- display week: locale calendar week only for the UI calendar, not physiology.

Add:

```swift
public struct RecoveryState: Sendable, Equatable {
    public let byExercise: [ExerciseKey: RecoveryWindow]
    public let byPattern: [MovementPattern: RecoveryWindow]
    public let byBodyPart: [BodyPart: RecoveryWindow]
    public let wholeBody: RecoveryWindow?
}

public struct RecoveryWindow: Sendable, Equatable {
    public let lastExposedAt: Date
    public let hardEligibleAt: Date
    public let reason: RecoveryReason
    public let confidence: FactConfidence
}
```

Add balance facts:

- strength days in rolling 7 days;
- major patterns/body parts trained;
- direct and fractional sets, explicitly named as estimates;
- moderate and vigorous aerobic minutes;
- moderate-equivalent minutes: `moderate + 2 * vigorous` for comparing against the 150-minute floor;
- easy/moderate/hard days and consecutive hard days;
- latest same-protocol VO₂max estimate and trend;
- readiness observation, if any;
- data completeness/confidence.

Do not combine field-test protocols by selecting the maximum. Trend only comparable measurements from the same protocol. A generic wearable VO₂max series is its own protocol.

### 4.4 Readiness check-in

Add an optional, once-daily `ReadinessEntry` with four 1–5 items:

- muscle soreness;
- fatigue/energy;
- sleep quality;
- stress/mood.

Add a separate yes/no “pain or illness concern” safety item. This is not part of a numeric wellness score. If yes, suppress intense recommendations and show neutral safety copy: “Choose rest or easy activity. If symptoms are concerning or persistent, seek qualified medical advice.” Do not attempt diagnosis.

Never require the check-in to use the app. Missing readiness lowers confidence and keeps conservative time gates.

### 4.5 Remove pseudo-precise volume landmarks

Deprecate `MEV`, `MAV`, and `MRV` naming and the fixed per-body-part thresholds. Replace with:

```swift
public struct VolumeGuidance {
    public let observedFractionalSets: Double
    public let startingTargetRange: ClosedRange<Double>?
    public let personalBaselineRange: ClosedRange<Double>?
    public let trend: DoseTrend
    public let confidence: FactConfidence
}
```

For general hypertrophy guidance, use a clearly labeled **starting range**, centered near the ACSM 2026 ~10 sets/muscle/week summary, then personalize from adherence, readiness, and multi-week response. Do not render a red “over MRV” state from set count alone.

Count direct sets as `1.0` and indirect sets as `0.5` only as a transparent estimation convention. Cite Pelland et al. 2026 for the fractional-set model; do not describe the 0.5 factor as settled physiology.

## 5. Eligibility policy

Create `SessionEligibilityPolicy.swift`. This stage must run before scoring and cannot be overridden by recommendation priority.

```swift
public enum EligibilityDecision: Sendable, Equatable {
    case eligible(notes: [DecisionNote])
    case defer(until: Date, reasons: [DecisionReason])
    case blocked(reasons: [DecisionReason])
}
```

Evaluate every candidate exercise and session.

### Hard gates

1. **Active workout:** never start a second session while a workout is active; show Resume.
2. **Exact lift:** defer loaded working sets for the same exercise until at least 24 hours after its last working set.
3. **Same hard pattern/body part:** default hard eligibility at 48 hours after a hard exposure.
4. **High fatigue:** use 72 hours when at least two are true: failure reported, high session set count, mean/max RPE ≥9, poor readiness, persistent performance decline. A single inferred flag is not enough.
5. **Unknown imported strength:** defer hard full-body strength 24 hours; allow easy aerobic activity; ask for workout details.
6. **Hard lower-body collision:** defer running intervals, sprinting, plyometrics, and hard cycling for 24 hours after hard squat/hinge work. Walking, easy cycling, and easy swimming may remain eligible.
7. **Pain/illness concern:** block hard training. Offer rest/easy movement with safety copy.
8. **Plan conflict:** a routine is eligible only if every hard main movement is eligible. Do not hide a recovering deadlift inside an otherwise eligible Pull routine.

### Soft modifiers after gates

- Prefer a different pattern when one region has been trained recently.
- Prefer easy aerobic work when strength minimum is met but aerobic moderate-equivalent minutes are behind.
- Prefer strength when aerobic target is on track but fewer than two strength days are planned/completed and muscles are eligible.
- Prefer rest/recovery when readiness is poor, hard days are accumulating, or no useful training candidate is eligible.
- Prefer user-enjoyed modalities and routines when physiologically equivalent.
- Avoid sudden volume jumps; compare the proposed session to the user's rolling 28-day baseline. Do not use a universal acute:chronic workload-ratio threshold.

Every defer/block decision must carry a user-readable reason and citation IDs where evidence applies.

## 6. Candidate sessions and weekly planner

### Candidate types

Add `CoachSession` with these top-level kinds:

- `.strength`
- `.easyAerobic`
- `.moderateAerobic`
- `.vo2Intervals`
- `.recovery`
- `.rest`
- `.assessment`

Each candidate contains duration, exercises/modality, intensity, training-load tags, citations, and a concrete launch payload. The payload shown on the card must be the payload launched by the CTA.

### Scoring order

After hard eligibility filtering, score in this order:

1. honor an active user-selected program and its next valid day;
2. close the largest weekly fitness gap (strength coverage vs. aerobic moderate-equivalent minutes);
3. preserve hard/easy rhythm and recovery;
4. progress a lift only when its session is eligible;
5. prefer adherence, equipment, time, and modality preferences;
6. prefer lower-risk/easier options when confidence is low.

Do not use the current global recommendation priorities (`deload 110`, `progression 100`, etc.) as the top-level session selector.

### Adaptive seven-day outline

Generate a rolling seven-day outline, recomputed after every completed/imported workout and readiness update. It is an outline, not a rigid calendar. When a user trains off-plan, consume the actual event and reflow future days.

Suggested templates are schedule shapes, not scientifically unique optima:

| Availability | Strength shape | Aerobic shape | Recovery intent |
|---|---|---|---|
| 2 strength days | Full Body A / Full Body B | 2–4 easy/moderate sessions; optional intervals when ready | ≥48 h between hard full-body sessions |
| 3 strength days | Alternating Full Body A/B | 2–3 aerobic sessions, mostly easy/moderate | No same hard lift on consecutive days |
| 4 strength days | Upper / Lower / Upper / Lower | 2–3 aerobic sessions | Avoid hard leg cardio adjacent to hard lower days |
| 5+ training days | User program, upper/lower or PPL variants | Aerobic work retained, not silently displaced | At least one easy/rest day as needed |

Do not default a general-fitness user into six-day PPL. If they explicitly select it, Coach should still fit aerobic work and recovery around it.

### Beginner full-body A/B

Replace the cold-start “3 sets each of squat, bench, deadlift” payload.

Example A:

- squat pattern: 2–3 sets;
- horizontal push: 2–3 sets;
- horizontal pull: 2–3 sets;
- optional carry/core: 1–2 sets.

Example B:

- hinge pattern: 1–2 working sets for deadlift or 2–3 for a lighter hinge;
- vertical push: 2–3 sets;
- vertical pull: 2–3 sets;
- unilateral leg/core: 1–2 sets.

Start at 2–3 RIR, teach movement selection, and progress from adherence/performance. Do not prescribe a load without a baseline.

## 7. Cardio and VO₂max policy

### Aerobic target display

Show two values:

- `82 / 150 moderate-equivalent min` for the public-health floor;
- `VO₂max 42.3 · stable` only when comparable repeated data exists.

Do not call 150 minutes “optimal.” Copy: “weekly health target” or “guideline floor.” Let users set a higher performance goal.

### Intensity classification

Use the strongest available signal and expose confidence:

1. recorded HR samples + personalized max/threshold;
2. interval protocol target;
3. session RPE/talk-test entry;
4. modality default only as low confidence.

Do not infer vigorous minutes from average HR alone when medication, sensor gaps, or an unvalidated max HR makes the classification unreliable.

### VO₂max programming

- Inactive/beginner: build consistency with 20–30 min tolerable moderate work, 2–3 times/week, progressing duration before intensity.
- Established aerobic base: mostly easy/moderate work plus at most one initial VO₂-focused interval session/week.
- Progress to 1–2 interval sessions/week only when recovery and preference support it.
- Use long-interval HIIT such as 4×4 as one option, not the universal default.
- SIT/Wingate work is advanced, high-fatigue, and opt-in; do not prescribe it merely because a Wingate assessment declined.

## 8. Recommendation and explanation model

Replace `Recommendation` as the sole hero input with:

```swift
public struct CoachDecision: Sendable, Identifiable {
    public let id: String
    public let generatedAt: Date
    public let primary: CoachSession
    public let alternatives: [CoachSession]
    public let deferred: [DeferredCandidate]
    public let observedFacts: [ObservedFact]
    public let weeklyBalance: WeeklyBalance
    public let confidence: FactConfidence
    public let citationIds: [String]
}
```

Required invariants:

- `primary.launchPayload` is exactly what the primary CTA launches.
- Every excluded hard session has an eligibility reason and `until` when calculable.
- A decision is recomputed from current queries; do not cache merely by calendar day.
- A completed workout invalidates the prior decision immediately.
- Science citations explain principles. Product-policy text explains the conservative threshold.

Keep lift progression details as `CoachSession` exercise targets. A deferred progression remains visible under “Later,” not as today's action.

## 9. UI implementation

### Home Coach card states

Implement explicit variants:

1. **Train:** eligible strength or hard cardio. Primary CTA: `Start <session>`.
2. **Easy aerobic:** behind aerobic target with strength recovery constraints. CTA: `Start easy cardio`.
3. **Recovery:** no useful hard session eligible. CTA: `Start recovery` and secondary `Take a rest day`.
4. **Rest/safety:** pain/illness concern or very poor readiness. No green “push” CTA.
5. **Resume:** active workout always supersedes Coach.

Each card shows:

- state eyebrow (`COACH · RECOVERY`);
- one direct headline;
- the most relevant recent event;
- recovery chips or the concrete session prescription;
- next hard eligibility time when relevant;
- weekly strength + aerobic context;
- `Why this today`.

### “Your week” screen

Add a planning surface showing:

- strength days vs. 2-day guideline floor;
- aerobic moderate-equivalent minutes vs. 150-minute floor;
- seven-day adaptive outline;
- hard/easy/rest labels;
- VO₂max latest/trend with protocol and date;
- tap-to-swap a planned session, filtered to eligible alternatives.

Do not show all green just because the user completed two workouts if both trained the same narrow pattern. Include major-pattern coverage as a secondary detail.

### “Why this today” screen

Sections in order:

1. `What you did` — exact relevant events/timestamps.
2. `What Coach ruled out` — deferred/blocked candidates and next eligible time.
3. `Why this won` — weekly deficit, recovery overlap, preference, and confidence.
4. `Evidence` — citation cards.
5. `Policy` — one plain-language line identifying conservative defaults.

### Accessibility

- Do not rely on green/red alone; pair color with symbol and text.
- Make the entire Coach card a containable accessibility group, but keep CTA and science links separately actionable.
- Use exact a11y labels for eligibility time and moderate-equivalent minutes.
- Dynamic Type must not truncate the recommendation, recovery reasons, or CTA.
- Add identifiers: `coach.card.state`, `.recentEvent`, `.nextEligible`, `.weeklyBalance`, `.whyToday`, `coach.week.*`, and `coach.decision.*`.

## 10. Science registry changes

Add citations with stable IDs:

- `acsmResistance2026`
- `whoPhysicalActivity2020`
- `usPhysicalActivity2018`
- `pellandDoseResponse2026`
- `ramosCampoSplit2024`
- `parejaBlancoRecovery2020`
- `sawMonitoring2016`
- `meeusenOvertraining2013`
- `schumannConcurrent2022`
- `crowleyVO2Intensity2022`
- `poonHIIT2024`

Correct the copy for existing `frequencyMeta`: volume-equated frequency has no meaningful independent hypertrophy effect; distribute volume based on schedule, quality, and recovery.

Update `docs/CITATIONS.md` with:

- the exact claim supported;
- population and important limitation;
- which rule/policy uses it;
- whether the threshold is evidence-backed or an app policy.

Citation tests must fail when a user-visible science claim references a missing ID.

## 11. File-by-file implementation order

### Phase 1 — reproduce and lock the bug

1. Add a failing test that logs a completed full-body workout at `now - 42 min` with squat, bench, deadlift.
2. Assert the current engine does not return/launch a deadlift progression as today's primary.
3. Add a test proving the CTA payload matches the card payload.

### Phase 2 — event and fact layer

- Add `TrainingEvent.swift`, `MovementPattern.swift`, and adapters.
- Extend `TrainingFacts` or introduce `CoachFacts`; prefer a new type if compatibility code would make semantics unclear.
- Pass strength, cardio, imported workouts, assessments, readiness, and `now` from Home.
- Convert calendar windows to rolling windows.
- Add pure tests before changing ranking.

### Phase 3 — eligibility and decision engine

- Add `SessionEligibilityPolicy.swift`.
- Add `CoachSession.swift`, `CoachDecision.swift`, `WeeklyPlan.swift`.
- Generate candidates, gate, then score.
- Keep old `RecommendationEngine` behind a temporary adapter only until UI migration.
- Remove `pickRoutine` from the Coach CTA path.

### Phase 4 — HealthKit integrity

- Preserve strength workout types on import.
- Deduplicate app-authored strength summaries.
- Backfill existing `.other` rows only when source metadata makes classification certain; otherwise retain unknown.

### Phase 5 — UI

- Replace `CoachCardView(recommendation:)` with `CoachCardView(decision:)`.
- Build explicit card states.
- Add “Your week” and “Why this today.”
- Ensure decision recomputes immediately on workout completion, deletion/restoration, import sync, and readiness change.

### Phase 6 — science cleanup

- Deprecate MEV/MAV/MRV UI and rules.
- Correct frequency claims.
- Replace single-week e1RM deload with repeated/corroborated plateau-fatigue logic.
- Audit every preset description so it says “informed by” rather than implying the exact routine was studied.
- Remove GVT 10×10 from automatic Coach selection; keep it only as a user-chosen advanced template with an evidence caveat, or remove it.

### Phase 7 — rollout

- Add a settings feature flag `recoveryAwareCoachV2` for one release.
- In debug builds, log candidate → eligibility → score → final decision without personal data.
- Provide a local decision export for bug reports.
- Remove the legacy engine after parity and migration tests pass.

## 12. Required test matrix

### Recovery invariants

- Full-body 42 minutes ago → deadlift/squat/bench progression deferred; easy aerobic or rest primary.
- Deadlift 23h59m ago → exact deadlift hard work deferred.
- Deadlift 24h01m ago but posterior chain hard exposure <48h → hard hinge still deferred by pattern gate.
- Low-volume technique work at low RPE + good readiness → policy can keep a non-hard technique candidate eligible, but not a hard progression.
- Failure/high RPE + poor readiness → 72h conservative window.
- Upper-body strength yesterday → easy run can be eligible; hard full-body routine containing bench is not.
- Lower-body strength today → sprint/HIIT run deferred; easy walk/cycle eligible.
- Unknown imported HealthKit strength today → hard full-body deferred, easy aerobic eligible.
- Pain/illness concern → hard candidates blocked; no diagnosis text.

### Balance and cardio

- Two strength days, zero aerobic minutes → moderate aerobic candidate outranks another eligible strength progression for general-fitness goal.
- Zero strength days, 150 aerobic-equivalent minutes, all muscles eligible → strength candidate wins.
- 75 vigorous minutes counts as 150 moderate-equivalent minutes.
- Missing HR intensity → minutes retain low-confidence classification; do not fabricate precision.
- Same-protocol VO₂max values trend; cross-protocol values do not.
- Beginner with no cardio history → moderate session, not SIT or 4×4, is primary.

### Rolling-window boundaries

- Sunday workout remains in facts on Monday if <7 days old.
- Events exactly outside 7 days drop out deterministically.
- `now` is injectable in every test; do not use wall-clock time in engine tests.
- In-progress sets block conflicts but do not count as completed weekly dose.

### UI and launch integrity

- Card state after the reported full-body case is Recovery/Easy Aerobic.
- `coach.card.nextEligible` contains tomorrow's time.
- “Why this today” lists deadlift under ruled out.
- Primary CTA launches the exact `CoachSession.launchPayload` shown.
- Deleting/restoring a workout recomputes the decision.
- Dynamic Type accessibility test does not truncate CTA or reason.

### Science integrity

- Every evidence claim has a citation.
- Every product heuristic is labeled policy.
- No output contains “overtrained” or “overtraining syndrome” as a diagnosis.
- No output calls 150 minutes universally optimal.
- No output calls fixed set bands MRV/MEV without individual evidence.

## 13. Acceptance criteria

The work is complete only when all are true:

1. The reported same-morning full-body → deadlift recommendation is covered by a deterministic regression test and cannot occur through the card or launched routine.
2. Coach consumes strength, cardio, imported HealthKit workouts, assessments, and optional readiness.
3. Today's hard recommendation is selected only after eligibility gates.
4. The weekly plan represents both strength and aerobic fitness.
5. The card payload and launched payload are identical.
6. Recovery times are inspectable and described as conservative policy.
7. Frequency, volume-landmark, deload, and preset science copy is corrected.
8. The app never claims to diagnose overtraining.
9. `swift test` passes in `CadenceCore`; app build and affected UI tests pass.
10. `docs/CITATIONS.md` and the in-app citation registry agree.

## 14. Explicit non-goals

- No medical diagnosis or injury prediction.
- No readiness score derived solely from HRV, resting HR, calories, or sleep from a wearable.
- No universal “optimal split.”
- No rigid 48-hour claim for every person/session.
- No black-box AI ranking.
- No recommendation to “make up” missed training by doubling the next day.
- No punishment, streak loss, or shame language for rest days.

The desired tone is competent and humane: rest and easy days are valid training decisions, aerobic capacity is a first-class fitness outcome, and the best split is the one that fits the user while preserving recoverable, progressive work.
