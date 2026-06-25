import Foundation

// MARK: - Phase 3: multi-system recommendation rules (2026-06-25 evidence upgrade)
//
// These rules read the richer `CoachFacts` (system loads, readiness, assessment
// coverage) and emit typed, cited `Recommendation`s covering strength blocks, volume
// personalization, aerobic base, VO₂, threshold, anaerobic opt-in, flexibility, and
// recovery/readiness. They are deterministic and pure. Phase 3 only *produces* them;
// the decision engine consumes them in Phase 4, so primary behavior is unchanged.
//
// Citation discipline: every rule's primary citation + extra citation IDs come from
// the claim category's pool (see `CitationRegistry.citationPool(for:)`).

public enum CoachRecommendationEngine {

    /// All system recommendations for the current facts, highest priority first.
    /// `anaerobicOptIn` gates the SIT/anaerobic lane — it is never produced for a
    /// non-advanced user who hasn't opted in.
    public static func run(_ facts: CoachFacts, anaerobicOptIn: Bool = false) -> [Recommendation] {
        var out: [Recommendation] = []
        out += recoveryReadiness(facts)
        out += strengthBlock(facts)
        out += volumePersonalization(facts)
        out += aerobicBase(facts)
        out += vo2Intervals(facts)
        out += thresholdTempo(facts)
        out += flexibility(facts)
        out += anaerobicOptInRule(facts, optedIn: anaerobicOptIn)
        out += assessmentPrompt(facts)

        var seen = Set<String>()
        let unique = out.filter { seen.insert($0.id).inserted }
        return unique.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            return a.id < b.id
        }
    }

    // MARK: helpers

    private static func cite(_ id: String) -> Citation {
        CitationRegistry.citation(forId: id) ?? CitationRegistry.schoenfeld2021
    }

    /// Distinct calendar weeks with a completed strength event in the trailing 28 days.
    private static func strengthWeeks(_ facts: CoachFacts) -> Int {
        let weeks = facts.rolling28dCompletedEvents
            .filter(\.isStrength)
            .map { WeeklyStats.weekStart(now: $0.start) }
        return Set(weeks).count
    }

    /// True if hard lower-body strength, VO₂, threshold, or anaerobic work happened in
    /// the last 72h — used to gate hard new prescriptions.
    private static func recentHardLowerOrHighIntensity(_ facts: CoachFacts) -> Bool {
        for e in facts.rolling72hCompletedEvents {
            if case .strength(let d) = e.kind, let det = d {
                if det.exercises.contains(where: { $0.isHard && $0.patterns.contains(where: \.isLowerBody) }) {
                    return true
                }
            }
            for ex in e.systemExposures where ex.hard
            && [.vo2max, .threshold, .anaerobicPower].contains(ex.system) {
                return true
            }
        }
        return false
    }

    // MARK: - C1 Strength block

    static func strengthBlock(_ facts: CoachFacts) -> [Recommendation] {
        let hasBaseline = facts.assessmentCoverage[.maximalStrength]?.hasBaseline ?? false
        guard strengthWeeks(facts) >= 2 || hasBaseline else { return [] }

        let range = facts.goal.repRange
        let rir = facts.goal.targetRIR
        let system: TrainingSystem
        let action: String
        switch facts.goal {
        case .strength:
            system = .maximalStrength
            action = "Run a 4–8 week strength block: heavy main lifts at \(range.lowerBound)–\(range.upperBound) reps, ~\(rir) RIR, with lower-volume accessories. Add load week to week, then take a lighter week."
        case .hypertrophy:
            system = .hypertrophy
            action = "Run a 4–8 week hypertrophy block: progress weekly sets at \(range.lowerBound)–\(range.upperBound) reps, ~\(rir) RIR, then deload before pushing volume again."
        case .endurance:
            system = .strengthEndurance
            action = "Run a 4–8 week block: higher-rep local-endurance work (\(range.lowerBound)–\(range.upperBound) reps) plus easy aerobic support."
        }
        return [Recommendation(
            id: "strengthBlock",
            kind: .strengthBlock,
            title: "Plan a \(facts.goal.displayName.lowercased()) block",
            action: action,
            detail: "Organizing training into blocks (periodization) produces greater strength gains than unstructured training, and the load/rep emphasis follows the repetition continuum for your goal. Effort is autoregulated by reps in reserve.",
            citation: cite("williamsLinearPeriodization"),
            citationIds: ["schoenfeld2021", "rpeAutoregulation"],
            target: SetTarget(sets: nil, repsLow: range.lowerBound, repsHigh: range.upperBound, loadKg: nil, rir: rir),
            confidence: .moderate,
            priority: 60,
            system: system,
            evidenceCategory: .periodization,
            whyNowFacts: ["\(strengthWeeks(facts)) week(s) of strength logged"],
            minimumEligibility: ["2+ weeks of strength history or a strength baseline"])]
    }

    // MARK: - C2 Volume personalization

    static func volumePersonalization(_ facts: CoachFacts) -> [Recommendation] {
        var out: [Recommendation] = []
        let readinessPoor = facts.readiness?.isPoor ?? false
        for (part, sets) in facts.weeklyBalance.fractionalSets where sets > 0 {
            let zone = VolumeLandmarks.zone(sets: sets, for: part, experience: facts.experience)
            let name = part.displayName
            switch zone {
            case .belowMEV:
                out.append(Recommendation(
                    id: "volumeAdjust.add.\(part.rawValue)",
                    kind: .volumeAdjust, part: part,
                    title: "Add \(name.lowercased()) volume",
                    action: "\(name) is on the low side this week (\(PrescriptionMath.sets(sets)) sets). Add 1–2 sets, ideally spread across 2 sessions, and judge by your own response before chasing more.",
                    detail: "Weekly sets per muscle drive growth in a graded dose-response. Start from a productive range and personalize from your own progress rather than fixed cutoffs. Spreading volume across at least two sessions a week helps you fit and recover it — frequency mainly distributes volume, it is not an independent dose.",
                    citation: cite("volumeDoseResponse"),
                    citationIds: ["pellandDoseResponse2026", "frequencyMeta"],
                    confidence: .moderate,
                    priority: 55,
                    system: .hypertrophy,
                    evidenceCategory: .strengthVolume,
                    whyNowFacts: ["\(name): \(PrescriptionMath.sets(sets)) sets/week"]))
            case .overMRV:
                if readinessPoor {
                    out.append(Recommendation(
                        id: "volumeAdjust.reduce.\(part.rawValue)",
                        kind: .volumeAdjust, part: part,
                        title: "Hold or trim \(name.lowercased()) volume",
                        action: "\(name) is high this week (\(PrescriptionMath.sets(sets)) sets) and your readiness is down. Hold volume steady or trim a couple of sets and reassess next week.",
                        detail: "More volume helps with diminishing returns, and adaptation depends on recovering the work you do. When self-reported readiness is poor, holding or slightly reducing volume is the conservative choice — this is a coaching cue, not a diagnosis.",
                        citation: cite("pellandDoseResponse2026"),
                        citationIds: ["volumeDoseResponse"],
                        confidence: .moderate,
                        priority: 56,
                        system: .hypertrophy,
                        evidenceCategory: .strengthVolume,
                        whyNowFacts: ["\(name): \(PrescriptionMath.sets(sets)) sets/week", "readiness down"]))
                }
            default:
                break
            }
        }
        return out
    }

    // MARK: - C3 Aerobic base

    static func aerobicBase(_ facts: CoachFacts) -> [Recommendation] {
        let stale = facts.systemLoads[.aerobicBase]?.isStale ?? true
        let easyMod = (facts.aerobicMinutesByBucket[.easy] ?? 0) + (facts.aerobicMinutesByBucket[.moderate] ?? 0)
        guard stale || easyMod <= 0 else { return [] }

        let action = facts.experience == .beginner
            ? "Build an aerobic base: 20–30 min of easy-to-moderate work (brisk walk, light cycle, easy swim) a couple of times a week. Progress duration before intensity."
            : "Add easy-to-moderate aerobic work: 20–45 min of steady effort. Build the habit and the duration first; intensity can come later."
        return [Recommendation(
            id: "aerobicBase",
            kind: .aerobicBase,
            title: "Build your aerobic base",
            action: action,
            detail: "Large pooled cohorts link more regular physical activity with better long-term health, with the biggest gains for people doing little now. There is no single best dose — steady, sustainable easy-to-moderate work builds the base that harder sessions later sit on top of.",
            citation: cite("ekelundActivityMortality2016"),
            citationIds: ["mooreLeisureActivity2012", "aremDoseResponse2015"],
            confidence: .moderate,
            priority: 50,
            system: .aerobicBase,
            evidenceCategory: .aerobicBase,
            whyNowFacts: ["No easy/moderate aerobic work logged this week"],
            minimumEligibility: facts.experience == .beginner ? ["progress duration before intensity"] : [])]
    }

    // MARK: - C4 VO₂ intervals

    static func vo2Intervals(_ facts: CoachFacts) -> [Recommendation] {
        guard facts.experience != .beginner else { return [] }
        let vo2Declined = facts.assessmentCoverage[.vo2max]?.trend == .declined
        let vo2Stale = facts.systemLoads[.vo2max]?.isStale ?? true
        guard vo2Declined || vo2Stale else { return [] }
        // Require an aerobic base and no recent hard lower-body/high-intensity collision.
        let baseExists = !(facts.systemLoads[.aerobicBase]?.isStale ?? true)
            || (facts.assessmentCoverage[.vo2max]?.hasBaseline ?? false)
        guard baseExists, !recentHardLowerOrHighIntensity(facts) else { return [] }

        return [Recommendation(
            id: "vo2Intervals",
            kind: .vo2Intervals,
            title: "Add a VO₂ interval session",
            action: "Try one session of long intervals — e.g. 4×4 min hard / 3 min easy, or 3×5 min — once a week. Add a second only if load and recovery clearly support it.",
            detail: "Interval training improves VO₂max; both intervals and steady continuous work help, with a small edge to higher intensity. One quality session a week is plenty for most people.",
            citation: cite("crowleyVO2Intensity2022"),
            citationIds: ["poonHIIT2024", "milanovicHIIT2015"],
            cardioPrescription: "Long intervals (e.g. 4×4)",
            confidence: .moderate,
            priority: 45,
            system: .vo2max,
            evidenceCategory: .vo2Training,
            whyNowFacts: vo2Declined ? ["VO₂ assessment trending down"] : ["No VO₂ work logged this week"],
            minimumEligibility: ["aerobic base", "intermediate or advanced"])]
    }

    // MARK: - C5 Threshold / tempo

    static func thresholdTempo(_ facts: CoachFacts) -> [Recommendation] {
        let baseExists = !(facts.systemLoads[.aerobicBase]?.isStale ?? true)
        let thresholdStale = facts.systemLoads[.threshold]?.isStale ?? true
        let vo2IsLimiter = facts.assessmentCoverage[.vo2max]?.trend == .declined
        guard baseExists, thresholdStale, !vo2IsLimiter else { return [] }

        let estimatedHR = facts.zoneSource == .ageEstimated
        let confidence: RecommendationConfidence = estimatedHR ? .low : .moderate
        var citationIds: [String] = []
        if estimatedHR { citationIds.append("tanakaMaxHR2001") }
        var risk: [String] = []
        if estimatedHR {
            risk.append("Your heart-rate zones use an age-estimated max, which varies a lot between people — go by feel (comfortably hard) as well as HR.")
        }
        return [Recommendation(
            id: "thresholdTempo",
            kind: .thresholdTempo,
            title: "Add a threshold/tempo session",
            action: "Add a steady-hard effort: e.g. 2×10 min or 20 min continuous at a 'comfortably hard' pace you could just hold a few words at.",
            detail: "Threshold work develops the pace you can sustain. Heart-rate, ventilatory, and lactate thresholds agree on average but vary between individuals, so prescriptions are approximate — anchor to perceived effort, not just a number.",
            citation: cite("kaufmannThreshold2023"),
            citationIds: citationIds,
            confidence: confidence,
            priority: 40,
            system: .threshold,
            evidenceCategory: .thresholdTraining,
            whyNowFacts: ["No threshold work logged this week"],
            riskNotes: risk,
            uncertainty: estimatedHR ? .low : .moderate)]
    }

    // MARK: - C6 Anaerobic opt-in (never auto-primary)

    static func anaerobicOptInRule(_ facts: CoachFacts, optedIn: Bool) -> [Recommendation] {
        guard facts.experience == .advanced || optedIn else { return [] }
        guard !recentHardLowerOrHighIntensity(facts) else { return [] }

        return [Recommendation(
            id: "anaerobicOptIn",
            kind: .anaerobicOptIn,
            title: "Optional: short sprint intervals",
            action: "If you want to develop anaerobic power, you could add short all-out efforts (e.g. 4–6 × 20–30 s sprints with full recovery). This is optional, not prescribed.",
            detail: "Sprint-interval training can improve fitness in little time, but it is very fatiguing and high-effort. Coach never schedules it for you — it is an opt-in lane.",
            citation: cite("slothSIT2013"),
            citationIds: ["wingateTest", "buchheitLaursenHIIT2013"],
            confidence: .moderate,
            priority: 15,
            system: .anaerobicPower,
            evidenceCategory: .anaerobicTraining,
            riskNotes: ["High fatigue and high effort.",
                        "Stop for pain, chest discomfort, or dizziness.",
                        "Requires your explicit opt-in — never auto-prescribed."],
            minimumEligibility: ["advanced, or explicitly opted in"])]
    }

    // MARK: - C7 Flexibility / mobility

    static func flexibility(_ facts: CoachFacts) -> [Recommendation] {
        let stale = facts.systemLoads[.flexibility]?.isStale ?? true
        guard stale else { return [] }
        return [Recommendation(
            id: "flexibility",
            kind: .flexibility,
            title: "Add some mobility work",
            action: "Spend 10–20 min on stretching or mobility for tight areas. Easy to fit on a rest or recovery day.",
            detail: "Regular stretching reliably increases range of motion over time. The benefit here is flexibility and ROM. Coach makes no broad injury-prevention claim for stretching alone.",
            citation: cite("konradStretchROM2024"),
            citationIds: ["behmStretching2016"],
            confidence: .moderate,
            priority: 35,
            system: .flexibility,
            evidenceCategory: .flexibilityROM,
            whyNowFacts: ["No mobility/flexibility work logged this week"])]
    }

    // MARK: - C8 Recovery & readiness

    static func recoveryReadiness(_ facts: CoachFacts) -> [Recommendation] {
        let readinessPoor = facts.readiness?.isPoor ?? false
        let consec = facts.weeklyBalance.consecutiveHardDays
        let spike = !facts.loadSpikeFlags.isEmpty
        let pain = facts.readiness?.painConcern ?? false
        guard readinessPoor || consec >= 3 || spike || pain else { return [] }

        var why: [String] = []
        if readinessPoor { why.append("Readiness is low") }
        if consec >= 3 { why.append("\(consec) hard days in a row") }
        if spike { why.append("Training load jumped recently") }

        return [Recommendation(
            id: "recoveryReadiness",
            kind: .recoveryReadiness,
            title: "Consider an easier day",
            action: pain
                ? "You flagged pain or illness — choose rest or gentle movement, and seek qualified advice if it persists."
                : "Today looks like a good day to back off: rest, an easy walk, mobility, or a lighter reduced-load session.",
            detail: "Self-reported soreness, sleep, stress, and energy track training load well and respond more consistently than most objective markers. Recovering the work you do is what lets it pay off. This is a conservative coaching cue based on your inputs — not a diagnosis.",
            citation: cite("sawMonitoring2016"),
            citationIds: ["halsonRecovery2014", "dupuyFatigue2018", "meeusenOvertraining2013"],
            confidence: .moderate,
            priority: 80,
            system: .recovery,
            evidenceCategory: .recoveryMonitoring,
            whyNowFacts: why,
            uncertainty: facts.readiness?.confidence ?? .low)]
    }

    // MARK: - C9 Assessment prompt

    static func assessmentPrompt(_ facts: CoachFacts) -> [Recommendation] {
        var out: [Recommendation] = []

        func missing(_ system: TrainingSystem) -> Bool {
            let c = facts.assessmentCoverage[system]
            return !(c?.hasBaseline ?? false) || !(c?.isFresh ?? false)
        }

        if missing(.vo2max), facts.experience != .beginner || !(facts.systemLoads[.aerobicBase]?.isStale ?? true) {
            out.append(Recommendation(
                id: "assessmentPrompt.vo2max",
                kind: .assessmentPrompt,
                title: "Test your aerobic fitness",
                action: "Run a Cooper 12-minute run (or 1.5-mile run / Rockport walk) so Coach can track VO₂max and tailor cardio.",
                detail: "Field run/walk tests give a usable VO₂max estimate validated against treadmill testing. A fresh baseline lets Coach prescribe and re-test like a study.",
                citation: cite("cooperVo2max"),
                confidence: .low,
                priority: 30,
                system: .vo2max,
                evidenceCategory: .fieldTestValidity,
                whyNowFacts: ["No fresh aerobic baseline"]))
        }

        if missing(.maximalStrength), strengthWeeks(facts) >= 1 {
            out.append(Recommendation(
                id: "assessmentPrompt.strength",
                kind: .assessmentPrompt,
                title: "Test your main lifts",
                action: "Run an Estimated 1RM test on your main lifts so Coach can prescribe specific loads.",
                detail: "Prediction equations estimate 1RM from a heavy set with reasonable accuracy at low reps. A baseline unlocks percentage-based load targets.",
                citation: cite("oneRMEstimation"),
                confidence: .low,
                priority: 31,
                system: .maximalStrength,
                evidenceCategory: .fieldTestValidity,
                whyNowFacts: ["No fresh strength baseline"]))
        }

        return out
    }
}
