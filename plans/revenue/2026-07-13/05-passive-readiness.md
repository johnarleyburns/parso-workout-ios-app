# Phase 4 — Passive readiness (the wedge)

**Branch:** `phase-4-passive-readiness`
**Depends on:** Phase 0 (docs/citation groundwork).
**Decision:** **D4 — read `decisions.md` before writing a single line of this phase.**

**This is the phase that justifies $79.99/yr.** It is also the phase most likely to
be implemented wrongly in a way that violates the project's HARD RULE. Read the
caveat.

---

## Problem

The coach is recovery-aware **in architecture** — `CoachFacts.swift` models
`RecoveryState`, `consecutiveHardDays`, `loadSpikeFlags`, and
`sessionsSinceDeloadByExercise`. But its readiness **input** is a self-reported
survey (`ReadinessEntry`: soreness, sleep quality, stress, motivation, pain
concern). Surveys do not get filled out.

Meanwhile the user's Apple Watch is already writing **HRV, sleep, and resting heart
rate** into HealthKit, and `Services/HealthKitProvider.swift` reads **none of them**
(it reads workouts, steps, heart rate, energy, and distance — and not `bodyMass`
either, despite `CLAUDE.md` claiming it).

Reading them costs nothing: a HealthKit read permission, data that never leaves the
device, and **no change to the Data Not Collected label**. And it produces the one
sentence no competitor can say:

> *"Your HRV is 18% below your baseline and you slept 5h 10m. The coach dropped
> today's squat to 80% and moved the volume to Thursday — here's the study."*

**Whoop charges $239/yr to tell you the first half of that and cannot tell you the
second half. Hevy, Strong, and Fitbod can tell you neither half.**

---

## ⚠️ The caveat — why "just read HRV" is wrong

The obvious implementation is *"replace the survey with HRV."* **Do not do this.**

The coach **already cites `sawMonitoring2016`** — *"Self-reported measures trump
objective monitoring."* Self-report was chosen **because the evidence favors it.**
Under the HARD RULE (every coaching output must cite navigable science), shipping a
coach claim that contradicts a citation the coach already carries is a
**correctness bug**.

The real problem is not that self-report is wrong. It is **compliance**.

**The design is fusion:**

- Passive signals are a **zero-friction prior**, always available.
- **Self-report wins wherever present** — exactly as `sawMonitoring2016` requires.
- A passive red flag **prompts** the check-in, which fixes compliance without
  contradicting the science.

---

## Steps

### 1. `Services/HealthKitProvider.swift` — new read types

- `HKQuantityType(.heartRateVariabilitySDNN)`
- `HKQuantityType(.restingHeartRate)`
- `HKQuantityType(.bodyMass)` — also makes the existing `CLAUDE.md` claim true
- `HKCategoryType(.sleepAnalysis)`

Update the `Info.plist` purpose strings. **The privacy label is unaffected** —
on-device HealthKit reads, zero egress. Still Data Not Collected.

### 2. New `CadenceCore/Sources/CadenceCore/PassiveReadiness.swift`

Pure, zero-I/O. This is the bulk of the test surface.

```swift
/// One day of passively-collected recovery data, read from HealthKit.
public struct PassiveReadinessSample: Sendable, Equatable {
    public let date: Date
    public let hrvSDNN: Double?     // ms
    public let restingHR: Double?   // bpm
    public let sleepHours: Double?
}

public enum PassiveReadinessLevel: Sendable, Equatable {
    case insufficientData   // the coach makes NO claim
    case normal
    case suppressed
    case stronglySuppressed
}

public struct PassiveReadinessSignal: Sendable, Equatable {
    public let level: PassiveReadinessLevel
    public let hrvDeviationPct: Double?     // vs personal baseline
    public let restingHRDeltaBpm: Double?
    public let sleepDebtHours: Double?
    public let citationIds: [String]        // HARD RULE — never empty for a claim
}

public enum PassiveReadinessAnalyzer {
    public static func signal(samples: [PassiveReadinessSample],
                              now: Date) -> PassiveReadinessSignal
}
```

**Rules — every threshold must be citation-backed, and conservative:**

- Baseline = trailing 28–60d mean. **Require ≥14 days of HRV data**, else
  `.insufficientData`.
- Compare a **7-day rolling mean** against baseline — never a single day. A single
  day's HRV is noise, and treating it as signal is precisely the false precision the
  project's own `AssessmentEvidencePolicy` warns against (Javaloyes, Vesterinen).
- HRV rolling mean < −10% of baseline → contributes `suppressed`; < −20% →
  `stronglySuppressed`.
- Resting HR ≥ +5 bpm over baseline → contributes.
- Sleep debt ≥ 2h vs the 14-day mean, **or** < 6h absolute → contributes.
- **`.insufficientData` is the default, not an edge case.** A two-day-old install
  must produce **no confident claim at all**. Test this explicitly — it is the case
  most likely to ship an embarrassing false positive to a brand-new user.

### 3. New `CadenceCore/Sources/CadenceCore/ReadinessFusion.swift`

D4, in code:

```swift
public enum ReadinessFusion {
    /// Fuses passive HealthKit signals with the user's self-report.
    ///
    /// Self-report is AUTHORITATIVE where present (`sawMonitoring2016`:
    /// self-reported measures outperform objective monitoring). Passive signals
    /// are a zero-friction prior that fills the (common) gap where no check-in
    /// exists, and — when strongly suppressed with no check-in — raise
    /// `promptCheckIn` so the app *asks* rather than *assumes*.
    public static func fuse(selfReport: ReadinessSnapshot?,
                            passive: PassiveReadinessSignal,
                            now: Date) -> ReadinessSnapshot
}
```

- Self-report within the last 24h → **authoritative**. Passive may add context and
  confidence but **may not override it**.
- No recent self-report → passive drives a **lower-confidence** readiness estimate.
  `FactConfidence` already models exactly this.
- Passive `.stronglySuppressed` + no self-report → set `promptCheckIn`.

### 4. `SystemLoad.swift` — extend `ReadinessSnapshot` additively

New **optional or defaulted** fields only (the repo's additive-schema rule — no
destructive migrations):

```swift
public let passive: PassiveReadinessSignal?
public var promptCheckIn: Bool = false
```

Keep the existing initializer source-compatible.

### 5. `CoachFacts.swift` — populate `readiness` via `ReadinessFusion`

The existing deferral gates and deload rules **already consume `readiness`**. So the
coach gets materially better **without re-architecting the decision engine**. That is
the whole reason to do the work at this layer.

### 6. HARD RULE — citations

Add to `CitationRegistry` (`Citation.swift`), `docs/CITATIONS.md`, and the
`CoachKnowledgeBase` changelog:

| ID | Paper |
|---|---|
| `javaloyesHRVGuided2019` | HRV-guided training prescription in cycling (*Int J Sports Physiol Perform*) |
| `vesterinenHRVGuided2016` | Individual endurance training prescription with HRV (*Med Sci Sports Exerc*) |
| `buchheitMonitoring2014` | Monitoring training status with HR measures (*Front Physiol*) |
| `cravenSleep2022` | Acute sleep loss and physical performance — systematic review + meta-analysis (*Sports Med*) |

**`sawMonitoring2016` is retained**, and now additionally cites the fusion rule
itself.

Every `PassiveReadinessSignal` carrying a claim must populate `citationIds`, and the
UI must render them with `CitationLink` — **never raw IDs**.

### 7. UI

Surface on the Coach card, with a tappable citation:

> *"HRV 18% below your baseline, 5h 10m sleep. Squat dropped to 80% today."*
> **The science ›**

---

## Tests — the bulk of this plan

**`PassiveReadinessAnalyzerTests`**
- baseline math
- each threshold at, above, and below its boundary
- **`.insufficientData` with <14 days of data** — no claim
- missing metrics: HRV only / sleep only / RHR only / none
- a flat-line baseline produces no false positive
- outlier robustness (one anomalous day does not flip the level)

**`ReadinessFusionTests`**
- **self-report beats a contradicting passive signal** — the D4 invariant. Name the
  test for it.
- passive-only path yields reduced `FactConfidence`
- `promptCheckIn` set **only** on `.stronglySuppressed` + no check-in
- a **stale** (>24h) self-report does *not* win

**`CoachFactsTests`**
- suppressed readiness propagates into the existing deferral and deload behavior

**`CitationIntegrityTests` / `CoachScientificValidationTests`**
- extend so that a science claim with a **missing** citation ID **fails CI**. This is
  the project's HARD RULE, mechanically enforced.

---

## Acceptance

- `swift test` green.
- Every new coaching claim renders a tappable citation; no raw IDs reach the UI.
- `.insufficientData` produces **no claim at all**.
- `docs/CITATIONS.md` and `CitationRegistry.all` are in sync (already CI-enforced).

## Commit

```
feat: passive readiness from HealthKit (HRV/sleep/RHR), fused with self-report per sawMonitoring2016
```
