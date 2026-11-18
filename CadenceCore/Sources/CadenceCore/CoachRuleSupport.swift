import Foundation

// MARK: - Phase 3: multi-system recommendation rules (2026-06-25 evidence upgrade)
//
// These rules read the richer `CoachFacts` (system loads, readiness, assessment
// coverage) and emit typed, cited `Recommendation`s covering strength blocks, volume
// personalization, aerobic base, VO₂, threshold, anaerobic power, flexibility, and
// recovery/readiness. They are deterministic and pure. Phase 3 only *produces* them;
// the decision engine consumes them in Phase 4, so primary behavior is unchanged.
//
// Citation discipline: every rule's primary citation + extra citation IDs come from
// the claim category's pool (see `CitationRegistry.citationPool(for:)`).

public enum CoachRecommendationEngine {

    /// All system recommendations for the current facts, highest priority first.
    /// The hard anaerobic/SIT lane is available by default when recovery and
    /// training history support it; repeated easier choices down-rank it through
    /// `profile` rather than removing it.
    public static func run(_ facts: CoachFacts,
                           profile: CoachPreferenceProfile = .empty,
                           anaerobicOptIn: Bool = true) -> [Recommendation] {
        _ = anaerobicOptIn
        var out: [Recommendation] = []
        out += recoveryReadiness(facts)
        out += strengthBlock(facts)
        out += volumePersonalization(facts)
        out += aerobicBase(facts)
        out += vo2Intervals(facts)
        out += thresholdTempo(facts)
        out += flexibility(facts)
        out += anaerobicRule(facts, profile: profile)
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
            action = {
                #if os(Linux)
                "Run a 4–8 week strength block: heavy main lifts at \(range.lowerBound)–\(range.upperBound) reps, ~\(rir) RIR, with lower-volume accessories. Add load week to week, then take a lighter week."
                #else
                String(localized: "Run a 4–8 week strength block: heavy main lifts at \(range.lowerBound)–\(range.upperBound) reps, ~\(rir) RIR, with lower-volume accessories. Add load week to week, then take a lighter week.", bundle: .module)
                #endif
            }()
        case .hypertrophy:
            system = .hypertrophy
            action = {
                #if os(Linux)
                "Run a 4–8 week hypertrophy block: progress weekly sets at \(range.lowerBound)–\(range.upperBound) reps, ~\(rir) RIR, then deload before pushing volume again."
                #else
                String(localized: "Run a 4–8 week hypertrophy block: progress weekly sets at \(range.lowerBound)–\(range.upperBound) reps, ~\(rir) RIR, then deload before pushing volume again.", bundle: .module)
                #endif
            }()
        case .endurance:
            system = .strengthEndurance
            action = {
                #if os(Linux)
                "Run a 4–8 week block: higher-rep local-endurance work (\(range.lowerBound)–\(range.upperBound) reps) plus easy aerobic support."
                #else
                String(localized: "Run a 4–8 week block: higher-rep local-endurance work (\(range.lowerBound)–\(range.upperBound) reps) plus easy aerobic support.", bundle: .module)
                #endif
            }()
        }
        return [Recommendation(
            id: "strengthBlock",
            kind: .strengthBlock,
            title: {
                #if os(Linux)
                "Plan a \(facts.goal.displayName.lowercased()) block"
                #else
                String(localized: "Plan a \(facts.goal.displayName.lowercased()) block", bundle: .module)
                #endif
            }(),
            action: action,
            detail: {
                #if os(Linux)
                "Organizing training into blocks (periodization) produces greater strength gains than unstructured training, and the load/rep emphasis follows the repetition continuum for your goal. Effort is autoregulated by reps in reserve."
                #else
                String(localized: "Organizing training into blocks (periodization) produces greater strength gains than unstructured training, and the load/rep emphasis follows the repetition continuum for your goal. Effort is autoregulated by reps in reserve.", bundle: .module)
                #endif
            }(),
            citation: cite("williamsLinearPeriodization"),
            citationIds: ["currierResistancePrescription2023", "schoenfeld2021", "rpeAutoregulation"],
            target: SetTarget(sets: nil, repsLow: range.lowerBound, repsHigh: range.upperBound, loadKg: nil, rir: rir),
            confidence: .moderate,
            priority: 60,
            system: system,
            evidenceCategory: .periodization,
            whyNowFacts: [{
                #if os(Linux)
                "\(strengthWeeks(facts)) weeks of strength logged"
                #else
                String(localized: "\(strengthWeeks(facts)) weeks of strength logged", bundle: .module)
                #endif
            }()],
            minimumEligibility: [{
                #if os(Linux)
                "2+ weeks of strength history or a strength baseline"
                #else
                String(localized: "2+ weeks of strength history or a strength baseline", bundle: .module)
                #endif
            }()])]
    }

    // MARK: - C2 Volume personalization

    static func volumePersonalization(_ facts: CoachFacts) -> [Recommendation] {
        var out: [Recommendation] = []
        let readinessPoor = facts.readiness?.isPoor ?? false
        for (group, sets) in facts.weeklyBalance.fractionalSets where sets > 0 {
            let zone = VolumeLandmarks.zone(sets: sets, for: group, experience: facts.experience)
            let bands = VolumeLandmarks.bands(for: group, experience: facts.experience)
            let name = group.displayName
            switch zone {
            case .belowMEV:
                let toAdd = min(4, max(1, Int((bands.mev - sets).rounded(.up))))
                out.append(Recommendation(
                    id: "volumeAdjust.add.\(group.rawValue)",
                    kind: .volumeAdjust, group: group,
                    title: {
                        #if os(Linux)
                        "Add \(name.lowercased()) volume"
                        #else
                        String(localized: "Add \(name.lowercased()) volume", bundle: .module)
                        #endif
                    }(),
                    action: {
                        #if os(Linux)
                        "\(name): \(Format.progress(done: sets, target: bands.mev, unit: "sets")) this week. Add about \(toAdd) sets, ideally spread across 2 sessions, and judge by your own response."
                        #else
                        String(localized: "\(name): \(Format.progress(done: sets, target: bands.mev, unit: "sets")) this week. Add about \(toAdd) sets, ideally spread across 2 sessions, and judge by your own response.", bundle: .module)
                        #endif
                    }(),
                    detail: {
                        #if os(Linux)
                        "Weekly sets per muscle drive growth in a graded dose-response. Start from a productive range and personalize from your own progress rather than fixed cutoffs. Spreading volume across at least two sessions a week helps you fit and recover it — frequency mainly distributes volume, it is not an independent dose."
                        #else
                        String(localized: "Weekly sets per muscle drive growth in a graded dose-response. Start from a productive range and personalize from your own progress rather than fixed cutoffs. Spreading volume across at least two sessions a week helps you fit and recover it — frequency mainly distributes volume, it is not an independent dose.", bundle: .module)
                        #endif
                    }(),
                    citation: cite("volumeDoseResponse"),
                    citationIds: ["pellandDoseResponse2026", "frequencyMeta"],
                    confidence: .moderate,
                    priority: 55,
                    system: .hypertrophy,
                    evidenceCategory: .strengthVolume,
                    whyNowFacts: [{
                        #if os(Linux)
                        "\(name): \(PrescriptionMath.sets(sets)) sets/week"
                        #else
                        String(localized: "\(name): \(PrescriptionMath.sets(sets)) sets/week", bundle: .module)
                        #endif
                    }()]))
            case .overMRV:
                if readinessPoor {
                    out.append(Recommendation(
                        id: "volumeAdjust.reduce.\(group.rawValue)",
                        kind: .volumeAdjust, group: group,
                        title: {
                            #if os(Linux)
                            "Hold or trim \(name.lowercased()) volume"
                            #else
                            String(localized: "Hold or trim \(name.lowercased()) volume", bundle: .module)
                            #endif
                        }(),
                        action: {
                            #if os(Linux)
                            "\(name): \(PrescriptionMath.sets(sets))/\(PrescriptionMath.sets(bands.mrv)) sets this week · \(PrescriptionMath.sets(sets - bands.mrv)) over the high end, and readiness is down. Hold steady or trim about \(max(1, Int((sets - bands.mrv).rounded(.up)))) sets and reassess next week."
                            #else
                            String(localized: "\(name): \(PrescriptionMath.sets(sets))/\(PrescriptionMath.sets(bands.mrv)) sets this week · \(PrescriptionMath.sets(sets - bands.mrv)) over the high end, and readiness is down. Hold steady or trim about \(max(1, Int((sets - bands.mrv).rounded(.up)))) sets and reassess next week.", bundle: .module)
                            #endif
                        }(),
                        detail: {
                            #if os(Linux)
                            "More volume helps with diminishing returns, and adaptation depends on recovering the work you do. When self-reported readiness is poor, holding or slightly reducing volume is the conservative choice — this is a coaching cue, not a diagnosis."
                            #else
                            String(localized: "More volume helps with diminishing returns, and adaptation depends on recovering the work you do. When self-reported readiness is poor, holding or slightly reducing volume is the conservative choice — this is a coaching cue, not a diagnosis.", bundle: .module)
                            #endif
                        }(),
                        citation: cite("pellandDoseResponse2026"),
                        citationIds: ["volumeDoseResponse"],
                        confidence: .moderate,
                        priority: 56,
                        system: .hypertrophy,
                        evidenceCategory: .strengthVolume,
                        whyNowFacts: [{
                            #if os(Linux)
                            "\(name): \(PrescriptionMath.sets(sets)) sets/week"
                            #else
                            String(localized: "\(name): \(PrescriptionMath.sets(sets)) sets/week", bundle: .module)
                            #endif
                        }(), "readiness down"]))
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
            ? {
                #if os(Linux)
                "Build an aerobic base: 20–30 min of easy-to-moderate work (brisk walk, light cycle, easy swim) a couple of times a week. Progress duration before intensity."
                #else
                String(localized: "Build an aerobic base: 20–30 min of easy-to-moderate work (brisk walk, light cycle, easy swim) a couple of times a week. Progress duration before intensity.", bundle: .module)
                #endif
            }()
            : {
                #if os(Linux)
                "Add easy-to-moderate aerobic work: 20–45 min of steady effort. Build the habit and the duration first; intensity can come later."
                #else
                String(localized: "Add easy-to-moderate aerobic work: 20–45 min of steady effort. Build the habit and the duration first; intensity can come later.", bundle: .module)
                #endif
            }()
        return [Recommendation(
            id: "aerobicBase",
            kind: .aerobicBase,
            title: {
                #if os(Linux)
                "Build your aerobic base"
                #else
                String(localized: "Build your aerobic base", bundle: .module)
                #endif
            }(),
            action: action,
            detail: {
                #if os(Linux)
                "Large pooled cohorts link more regular physical activity with better long-term health, with the biggest gains for people doing little now. There is no single best dose — steady, sustainable easy-to-moderate work builds the base that harder sessions later sit on top of."
                #else
                String(localized: "Large pooled cohorts link more regular physical activity with better long-term health, with the biggest gains for people doing little now. There is no single best dose — steady, sustainable easy-to-moderate work builds the base that harder sessions later sit on top of.", bundle: .module)
                #endif
            }(),
            citation: cite("ekelundActivityMortality2016"),
            citationIds: ["mooreLeisureActivity2012", "aremDoseResponse2015"],
            confidence: .moderate,
            priority: 50,
            system: .aerobicBase,
            evidenceCategory: .aerobicBase,
            whyNowFacts: [{
                #if os(Linux)
                "No easy/moderate aerobic work logged this week"
                #else
                String(localized: "No easy/moderate aerobic work logged this week", bundle: .module)
                #endif
            }()],
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
            title: {
                #if os(Linux)
                "Add a VO₂ interval session"
                #else
                String(localized: "Add a VO₂ interval session", bundle: .module)
                #endif
            }(),
            action: {
                #if os(Linux)
                "Try one session of long intervals — e.g. 4×4 min hard / 3 min easy, or 3×5 min — once a week. Add a second only if load and recovery clearly support it."
                #else
                String(localized: "Try one session of long intervals — e.g. 4×4 min hard / 3 min easy, or 3×5 min — once a week. Add a second only if load and recovery clearly support it.", bundle: .module)
                #endif
            }(),
            detail: {
                #if os(Linux)
                "Interval training improves VO₂max; both intervals and steady continuous work help, with a small edge to higher intensity. One quality session a week is plenty for most people."
                #else
                String(localized: "Interval training improves VO₂max; both intervals and steady continuous work help, with a small edge to higher intensity. One quality session a week is plenty for most people.", bundle: .module)
                #endif
            }(),
            citation: cite("crowleyVO2Intensity2022"),
            citationIds: ["poonHIIT2024", "milanovicHIIT2015"],
            cardioPrescription: {
                #if os(Linux)
                "Long intervals (e.g. 4×4)"
                #else
                String(localized: "Long intervals (e.g. 4×4)", bundle: .module)
                #endif
            }(),
            confidence: .moderate,
            priority: 45,
            system: .vo2max,
            evidenceCategory: .vo2Training,
            whyNowFacts: vo2Declined ? ["VO₂ assessment trending down"] : [{
                #if os(Linux)
                "No VO₂ work logged this week"
                #else
                String(localized: "No VO₂ work logged this week", bundle: .module)
                #endif
            }()],
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
            risk.append({
                #if os(Linux)
                "Your heart-rate zones use an age-estimated max, which varies a lot between people — go by feel (comfortably hard) as well as HR."
                #else
                String(localized: "Your heart-rate zones use an age-estimated max, which varies a lot between people — go by feel (comfortably hard) as well as HR.", bundle: .module)
                #endif
            }())
        }
        return [Recommendation(
            id: "thresholdTempo",
            kind: .thresholdTempo,
            title: {
                #if os(Linux)
                "Add a threshold/tempo session"
                #else
                String(localized: "Add a threshold/tempo session", bundle: .module)
                #endif
            }(),
            action: {
                #if os(Linux)
                "Add a steady-hard effort: e.g. 2×10 min or 20 min continuous at a 'comfortably hard' pace you could just hold a few words at."
                #else
                String(localized: "Add a steady-hard effort: e.g. 2×10 min or 20 min continuous at a 'comfortably hard' pace you could just hold a few words at.", bundle: .module)
                #endif
            }(),
            detail: {
                #if os(Linux)
                "Threshold work develops the pace you can sustain. Heart-rate, ventilatory, and lactate thresholds agree on average but vary between individuals, so prescriptions are approximate — anchor to perceived effort, not just a number."
                #else
                String(localized: "Threshold work develops the pace you can sustain. Heart-rate, ventilatory, and lactate thresholds agree on average but vary between individuals, so prescriptions are approximate — anchor to perceived effort, not just a number.", bundle: .module)
                #endif
            }(),
            citation: cite("kaufmannThreshold2023"),
            citationIds: citationIds,
            confidence: confidence,
            priority: 40,
            system: .threshold,
            evidenceCategory: .thresholdTraining,
            whyNowFacts: [{
                #if os(Linux)
                "No threshold work logged this week"
                #else
                String(localized: "No threshold work logged this week", bundle: .module)
                #endif
            }()],
            riskNotes: risk,
            uncertainty: estimatedHR ? .low : .moderate)]
    }

    // MARK: - C6 Anaerobic / SIT default lane

    static func anaerobicRule(_ facts: CoachFacts,
                              profile: CoachPreferenceProfile = .empty) -> [Recommendation] {
        guard facts.experience != .beginner else { return [] }
        let baseExists = !(facts.systemLoads[.aerobicBase]?.isStale ?? true)
            || (facts.assessmentCoverage[.vo2max]?.hasBaseline ?? false)
        guard baseExists else { return [] }
        guard !recentHardLowerOrHighIntensity(facts) else { return [] }

        let tags = ["aerobic", "hard", "highImpact", "anaerobic"]
        let penalty = profile.avoidancePenalty(forTags: tags)
        let priority = max(5, 34 - penalty)
        return [Recommendation(
            id: "anaerobicOptIn",
            kind: .anaerobicOptIn,
            title: {
                #if os(Linux)
                "Short sprint intervals"
                #else
                String(localized: "Short sprint intervals", bundle: .module)
                #endif
            }(),
            action: {
                #if os(Linux)
                "Add short all-out efforts only if you feel ready today: e.g. 4–6 × 20–30 s sprints with full recovery."
                #else
                String(localized: "Add short all-out efforts only if you feel ready today: e.g. 4–6 × 20–30 s sprints with full recovery.", bundle: .module)
                #endif
            }(),
            detail: {
                #if os(Linux)
                "Sprint-interval training can improve fitness in little time, but it is very fatiguing and high-effort. Coach keeps it in the plan when you are eligible, then learns from your choices: if you keep skipping it or choosing easier work, it will rank lower over time."
                #else
                String(localized: "Sprint-interval training can improve fitness in little time, but it is very fatiguing and high-effort. Coach keeps it in the plan when you are eligible, then learns from your choices: if you keep skipping it or choosing easier work, it will rank lower over time.", bundle: .module)
                #endif
            }(),
            citation: cite("slothSIT2013"),
            citationIds: ["wingateTest", "buchheitLaursenHIIT2013"],
            confidence: .moderate,
            priority: priority,
            system: .anaerobicPower,
            evidenceCategory: .anaerobicTraining,
            riskNotes: [{
                #if os(Linux)
                "High fatigue and high effort."
                #else
                String(localized: "High fatigue and high effort.", bundle: .module)
                #endif
            }(),
                        {
                            #if os(Linux)
                            "Stop for pain, chest discomfort, or dizziness."
                            #else
                            String(localized: "Stop for pain, chest discomfort, or dizziness.", bundle: .module)
                            #endif
                        }(),
                        {
                            #if os(Linux)
                            "If you usually choose easier alternatives, Coach will lower this in the future."
                            #else
                            String(localized: "If you usually choose easier alternatives, Coach will lower this in the future.", bundle: .module)
                            #endif
                        }()],
            minimumEligibility: ["aerobic base", "intermediate or advanced"])]
    }

    // MARK: - C7 Flexibility / mobility

    static func flexibility(_ facts: CoachFacts) -> [Recommendation] {
        let stale = facts.systemLoads[.flexibility]?.isStale ?? true
        guard stale else { return [] }
        return [Recommendation(
            id: "flexibility",
            kind: .flexibility,
            title: {
                #if os(Linux)
                "Add some mobility work"
                #else
                String(localized: "Add some mobility work", bundle: .module)
                #endif
            }(),
            action: {
                #if os(Linux)
                "Spend 10–20 min on stretching or mobility for tight areas. Easy to fit on a rest or recovery day."
                #else
                String(localized: "Spend 10–20 min on stretching or mobility for tight areas. Easy to fit on a rest or recovery day.", bundle: .module)
                #endif
            }(),
            detail: {
                #if os(Linux)
                "Regular stretching reliably increases range of motion over time. The benefit here is flexibility and ROM. Coach makes no broad injury-prevention claim for stretching alone."
                #else
                String(localized: "Regular stretching reliably increases range of motion over time. The benefit here is flexibility and ROM. Coach makes no broad injury-prevention claim for stretching alone.", bundle: .module)
                #endif
            }(),
            citation: cite("konradStretchROM2024"),
            citationIds: ["behmStretching2016"],
            confidence: .moderate,
            priority: 35,
            system: .flexibility,
            evidenceCategory: .flexibilityROM,
            whyNowFacts: [{
                #if os(Linux)
                "No mobility/flexibility work logged this week"
                #else
                String(localized: "No mobility/flexibility work logged this week", bundle: .module)
                #endif
            }()])]
    }

    // MARK: - C8 Recovery & readiness

    static func recoveryReadiness(_ facts: CoachFacts) -> [Recommendation] {
        let readinessPoor = facts.readiness?.isPoor ?? false
        let consec = facts.weeklyBalance.consecutiveHardDays
        let spike = !facts.loadSpikeFlags.isEmpty
        let pain = facts.readiness?.painConcern ?? false
        guard readinessPoor || consec >= 3 || spike || pain else { return [] }

        var why: [String] = []
        if readinessPoor { why.append({
            #if os(Linux)
            "Readiness is low"
            #else
            String(localized: "Readiness is low", bundle: .module)
            #endif
        }()) }
        if consec >= 3 { why.append({
            #if os(Linux)
            "\(consec) hard days in a row"
            #else
            String(localized: "\(consec) hard days in a row", bundle: .module)
            #endif
        }()) }
        if spike { why.append({
            #if os(Linux)
            "Training load jumped recently"
            #else
            String(localized: "Training load jumped recently", bundle: .module)
            #endif
        }()) }

        return [Recommendation(
            id: "recoveryReadiness",
            kind: .recoveryReadiness,
            title: {
                #if os(Linux)
                "Consider an easier day"
                #else
                String(localized: "Consider an easier day", bundle: .module)
                #endif
            }(),
            action: pain
                ? {
                    #if os(Linux)
                    "You flagged pain or illness — choose rest or gentle movement, and seek qualified advice if it persists."
                    #else
                    String(localized: "You flagged pain or illness — choose rest or gentle movement, and seek qualified advice if it persists.", bundle: .module)
                    #endif
                }()
                : {
                    #if os(Linux)
                    "Today looks like a good day to back off: rest, an easy walk, mobility, or a lighter reduced-load session."
                    #else
                    String(localized: "Today looks like a good day to back off: rest, an easy walk, mobility, or a lighter reduced-load session.", bundle: .module)
                    #endif
                }(),
            detail: {
                #if os(Linux)
                "Self-reported soreness, sleep, stress, and energy track training load well and respond more consistently than most objective markers. Recovering the work you do is what lets it pay off. This is a conservative coaching cue based on your inputs — not a diagnosis."
                #else
                String(localized: "Self-reported soreness, sleep, stress, and energy track training load well and respond more consistently than most objective markers. Recovering the work you do is what lets it pay off. This is a conservative coaching cue based on your inputs — not a diagnosis.", bundle: .module)
                #endif
            }(),
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
                title: {
                    #if os(Linux)
                    "Add a VO₂ test baseline"
                    #else
                    String(localized: "Add a VO₂ test baseline", bundle: .module)
                    #endif
                }(),
                action: {
                    #if os(Linux)
                    "Run a Cooper 12-minute run (or 1.5-mile run / Rockport walk) so Coach can track VO₂max and tailor cardio."
                    #else
                    String(localized: "Run a Cooper 12-minute run (or 1.5-mile run / Rockport walk) so Coach can track VO₂max and tailor cardio.", bundle: .module)
                    #endif
                }(),
                detail: {
                    #if os(Linux)
                    "Your workout history and assessment baselines are different things. Logged workouts let Coach see training habits; one standardized VO₂ field test gives Coach a measured aerobic baseline for trend checks and interval recommendations."
                    #else
                    String(localized: "Your workout history and assessment baselines are different things. Logged workouts let Coach see training habits; one standardized VO₂ field test gives Coach a measured aerobic baseline for trend checks and interval recommendations.", bundle: .module)
                    #endif
                }(),
                citation: cite("cooperVo2max"),
                confidence: .low,
                priority: 30,
                system: .vo2max,
                evidenceCategory: .fieldTestValidity,
                whyNowFacts: [{
                    #if os(Linux)
                    "Need 1 standardized VO₂ field test; logged workouts do not replace this test baseline"
                    #else
                    String(localized: "Need 1 standardized VO₂ field test; logged workouts do not replace this test baseline", bundle: .module)
                    #endif
                }()]))
        }

        if missing(.maximalStrength), strengthWeeks(facts) >= 1 {
            out.append(Recommendation(
                id: "assessmentPrompt.strength",
                kind: .assessmentPrompt,
                title: {
                    #if os(Linux)
                    "Add a strength test baseline"
                    #else
                    String(localized: "Add a strength test baseline", bundle: .module)
                    #endif
                }(),
                action: {
                    #if os(Linux)
                    "Run an Estimated 1RM test on your main lifts so Coach can prescribe specific loads."
                    #else
                    String(localized: "Run an Estimated 1RM test on your main lifts so Coach can prescribe specific loads.", bundle: .module)
                    #endif
                }(),
                detail: {
                    #if os(Linux)
                    "Your logged workouts are enough for volume and habit trends. A separate e1RM or rep-max test gives Coach a measured strength baseline, which unlocks percentage-based load targets and cleaner retest comparisons."
                    #else
                    String(localized: "Your logged workouts are enough for volume and habit trends. A separate e1RM or rep-max test gives Coach a measured strength baseline, which unlocks percentage-based load targets and cleaner retest comparisons.", bundle: .module)
                    #endif
                }(),
                citation: cite("oneRMEstimation"),
                confidence: .low,
                priority: 31,
                system: .maximalStrength,
                evidenceCategory: .fieldTestValidity,
                whyNowFacts: [{
                    #if os(Linux)
                    "Need 1 e1RM or rep-max test for a main lift; workout count alone does not create this assessment baseline"
                    #else
                    String(localized: "Need 1 e1RM or rep-max test for a main lift; workout count alone does not create this assessment baseline", bundle: .module)
                    #endif
                }()]))
        }

        return out
    }
}
