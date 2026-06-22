import Foundation

/// One forward-chaining prescriptive rule: given the user's `TrainingFacts`, emit
/// zero or more cited `Recommendation`s. Pure and isolated so each is individually
/// testable (§03), mirroring `InsightRule`. `priority` ranks within the engine.
public struct RecommendationRule: Sendable {
    public let id: String
    public let priority: Int
    public let produce: @Sendable (TrainingFacts) -> [Recommendation]

    public init(id: String, priority: Int, produce: @escaping @Sendable (TrainingFacts) -> [Recommendation]) {
        self.id = id
        self.priority = priority
        self.produce = produce
    }
}

/// The bundled P5 prescriptive rule set — the action-producing half of the
/// Scientific Expert Engine. Each rule cites published work (`CitationRegistry`)
/// and stays conservative/non-medical (D3/D6). Lives alongside the read-only
/// `KnowledgeBase` insight rules.
public extension KnowledgeBase {

    /// Smallest load step the engine prescribes when adding weight (canonical kg).
    /// A 2.5 kg plate pair is the common default; lifts are rounded to this grid.
    static let loadIncrementKg = 2.5

    static let p5Rules: [RecommendationRule] = [
        deload,
        progression,
        addVolume,
    ]

    /// P6 cardio rules — prescribe interval protocols when cardio assessments
    /// show a decline.
    static let p6RecRules: [RecommendationRule] = [
        cardioHIIT,
        cardioSIT,
        missingBaseline,
    ]

    /// All active prescriptive rules.
    static let activeRecommendationRules: [RecommendationRule] = p5Rules + p6RecRules

    // MARK: - Rule: double-progression for a lift that isn't declining

    static let progression = RecommendationRule(id: "progression", priority: 100) { facts in
        let range = facts.goal.repRange
        let rir = facts.goal.targetRIR
        var out: [Recommendation] = []
        for snap in facts.liftSnapshots.values where snap.topSetWeightKg > 0 {
            if snap.trend == .declining { continue }
            let confidence: RecommendationConfidence = snap.trend == .flat ? .high : .moderate
            let lift = snap.exercise
            let assessedE1RM = facts.assessedE1RMs[lift]
            let target: SetTarget
            let action: String
            if snap.topSetReps < range.upperBound {
                if let e1rm = assessedE1RM {
                    let goalLoad = PrescriptionMath.roundLoad(e1rm * facts.goal.targetLoadPercentage)
                    if snap.topSetWeightKg < goalLoad * 0.90 {
                        target = SetTarget(sets: nil, repsLow: range.lowerBound, repsHigh: range.lowerBound,
                                           loadKg: goalLoad, rir: rir)
                        action = "Your assessed 1RM supports a higher working load — try \(SetTarget.trimmed(goalLoad)) kg (\(Int(facts.goal.targetLoadPercentage * 100))% of your tested 1RM)."
                    } else {
                        let nextReps = snap.topSetReps + 1
                        target = SetTarget(sets: nil, repsLow: nextReps, repsHigh: nextReps,
                                           loadKg: snap.topSetWeightKg, rir: rir)
                        action = "Add a rep on your top set at the same load — keep going until you reach \(range.upperBound)."
                    }
                } else {
                    let nextReps = snap.topSetReps + 1
                    target = SetTarget(sets: nil, repsLow: nextReps, repsHigh: nextReps,
                                       loadKg: snap.topSetWeightKg, rir: rir)
                    action = "Add a rep on your top set at the same load — keep going until you reach \(range.upperBound)."
                }
            } else {
                if let e1rm = assessedE1RM {
                    let goalLoad = PrescriptionMath.roundLoad(e1rm * facts.goal.targetLoadPercentage)
                    let incrementLoad = PrescriptionMath.roundLoad(snap.topSetWeightKg + loadIncrementKg)
                    let nextLoad = max(goalLoad, incrementLoad)
                    target = SetTarget(sets: nil, repsLow: range.lowerBound, repsHigh: range.lowerBound,
                                       loadKg: nextLoad, rir: rir)
                    action = "You hit \(range.upperBound) reps — move to \(SetTarget.trimmed(nextLoad)) kg (\(Int(facts.goal.targetLoadPercentage * 100))% of your tested 1RM) and reset to \(range.lowerBound)."
                } else {
                    let nextLoad = PrescriptionMath.roundLoad(snap.topSetWeightKg + loadIncrementKg)
                    target = SetTarget(sets: nil, repsLow: range.lowerBound, repsHigh: range.lowerBound,
                                       loadKg: nextLoad, rir: rir)
                    action = "You hit \(range.upperBound) reps — add a little load and drop back to \(range.lowerBound)."
                }
            }
            out.append(Recommendation(
                id: "progression.\(lift)",
                kind: .progression, part: snap.part, exercise: lift,
                title: "Progress your \(lift.lowercased())",
                action: action,
                detail: "Progressive overload drives strength and size: within a rep range, add reps to the top of the range first, then add load and reset — autoregulated by reps in reserve (RIR). Your \(facts.goal.displayName.lowercased()) range is \(range.lowerBound)–\(range.upperBound) reps at about \(rir) RIR.\(assessedE1RM != nil ? " Your assessed 1RM anchors the prescribed load." : "")",
                citation: CitationRegistry.rpeAutoregulation,
                citationIds: assessedE1RM != nil ? ["oneRMEstimation"] : [],
                target: target,
                confidence: confidence,
                priority: 100))
        }
        return out
    }

    // MARK: - Rule: deload a lift whose estimated 1RM is declining

    static let deload = RecommendationRule(id: "deload", priority: 110) { facts in
        let range = facts.goal.repRange
        var out: [Recommendation] = []
        for snap in facts.liftSnapshots.values where snap.trend == .declining && snap.topSetWeightKg > 0 {
            let lift = snap.exercise
            let backedOff = PrescriptionMath.roundLoad(snap.topSetWeightKg * 0.9)
            let easierRIR = max(facts.goal.targetRIR + 1, 3)
            let target = SetTarget(sets: 2, repsLow: range.lowerBound, repsHigh: range.upperBound,
                                   loadKg: backedOff, rir: easierRIR)
            out.append(Recommendation(
                id: "deload.\(lift)",
                kind: .deload, part: snap.part, exercise: lift,
                title: "Back off your \(lift.lowercased())",
                action: "Your estimated 1RM is sliding — take one lighter week (about 10% off, fewer sets), then push again.",
                detail: "A declining estimated 1RM alongside hard training usually means accumulated fatigue is outrunning recovery. A short, lighter week with more reps in reserve lets you recover and dissipate fatigue, so the next block can progress again. This is a coaching cue, not a medical one.",
                citation: CitationRegistry.rpeAutoregulation,
                target: target,
                confidence: .moderate,
                priority: 110))
        }
        return out
    }

    // MARK: - Rule: add weekly sets for a body part below MEV

    static let addVolume = RecommendationRule(id: "addVolume", priority: 90) { facts in
        let range = facts.goal.repRange
        let rir = facts.goal.targetRIR
        var out: [Recommendation] = []
        for part in BodyPart.allCases {
            guard let current = facts.weeklySetsByPart[part], current > 0 else { continue }
            let bands = VolumeLandmarks.bands(for: part, experience: facts.experience)
            guard current < bands.mev else { continue }
            let toAdd = min(4, max(1, Int((bands.mev - current).rounded(.up))))
            let name = part.displayName
            out.append(Recommendation(
                id: "addVolume.\(part.rawValue)",
                kind: .addVolume, part: part,
                title: "Add \(name.lowercased()) volume",
                action: "Add about \(toAdd) set\(toAdd == 1 ? "" : "s") of \(name.lowercased()) work this week.",
                detail: "Weekly sets per muscle drive growth in a dose-response fashion, with a minimum effective volume below which there's little adaptation. \(name) is under that threshold (~\(PrescriptionMath.sets(bands.mev)) sets/week for your experience level); adding a couple of sets lands it in the productive range.",
                citation: CitationRegistry.volumeDoseResponse,
                target: SetTarget(sets: toAdd, repsLow: range.lowerBound, repsHigh: range.upperBound,
                                  loadKg: nil, rir: rir),
                confidence: .moderate,
                priority: 90))
        }
        return out
    }

    /// The cold-start prescription: a sensible first session derived from the user's
    /// goal + experience, shown before there's any history to reason about so the
    /// Coach card is never empty (mirrors `InsightEngine.coldStart`).
    static func starter(goal: TrainingGoal, experience: ExperienceLevel) -> Recommendation {
        let range = goal.repRange
        let rir = goal.targetRIR
        return Recommendation(
            id: "starter",
            kind: .starter,
            title: "Start with a full-body session",
            action: "New here? Do a simple full-body session: about 3 sets per movement, \(range.lowerBound)–\(range.upperBound) reps, leaving ~\(rir) in reserve.",
            detail: "With no history yet, a full-body session a few times a week is a well-supported starting point: it trains each muscle often, keeps volume manageable, and gives the coach data to work from. Log a few sessions and the recommendations get specific to your lifts.",
            citation: CitationRegistry.schoenfeld2021,
            target: SetTarget(sets: 3, repsLow: range.lowerBound, repsHigh: range.upperBound, loadKg: nil, rir: rir),
            confidence: .moderate,
            priority: 0)
    }

    // MARK: - P6: cardio HIIT prescriptions

    /// When VO₂max is declining, prescribe high-intensity interval training
    /// (Norwegian 4×4 as the default, well-studied protocol for VO₂max improvement).
    private static let vo2maxKinds: Set<AssessmentKind> = [.vo2maxField, .cooper12min, .run1_5mile, .rockportWalk, .queensCollegeStep]

    static let cardioHIIT = RecommendationRule(id: "cardio.hiit", priority: 85) { facts in
        var out: [Recommendation] = []
        for s in facts.assessments where vo2maxKinds.contains(s.kind) && s.trend == .declined {
            let label = AssessmentFormat.seriesLabel(s)
            out.append(Recommendation(
                id: "cardio.hiit.vo2max",
                kind: .cardioHIIT,
                title: "Boost your aerobic fitness",
                action: "Try a Norwegian 4×4 session: warm up, then 4 rounds of 4 minutes hard / 3 minutes recovery, cool down.",
                detail: "High-intensity intervals are one of the most effective ways to raise VO₂max. Your \(label.lowercased()) is declining — one or two interval sessions a week, paired with your usual training, can reverse that trend in a 6–8 week block.",
                citation: CitationRegistry.hiitVo2max,
                cardioPrescription: "Norwegian 4×4",
                confidence: .moderate,
                priority: 85))
        }
        return out
    }

    /// When Wingate peak power is declining, prescribe sprint interval training.
    static let cardioSIT = RecommendationRule(id: "cardio.sit", priority: 84) { facts in
        var out: [Recommendation] = []
        for s in facts.assessments where s.kind == .wingate && s.trend == .declined {
            let label = AssessmentFormat.seriesLabel(s)
            out.append(Recommendation(
                id: "cardio.sit.wingate",
                kind: .cardioHIIT,
                title: "Build your anaerobic power",
                action: "Try a SIT (Wingate) session: warm up, then 4 rounds of 30s all-out sprint / 4 min recovery, cool down.",
                detail: "Sprint interval training is the most direct way to improve anaerobic peak power — the same energy pathway the Wingate test measures. Your \(label.lowercased()) is declining; one SIT session a week for a few weeks can restore it.",
                citation: CitationRegistry.wingateTest,
                cardioPrescription: "SIT (Wingate)",
                confidence: .moderate,
                priority: 84))
        }
        return out
    }

    // MARK: - Rule: prompt to run missing assessments (FR-12.3)

    static let missingBaseline = RecommendationRule(id: "missingBaseline", priority: 50) { facts in
        guard !facts.hasAnyAssessment else { return [] }
        guard facts.totalWorkingSets >= 3 else { return [] }
        return [Recommendation(
            id: "missingBaseline.strength",
            kind: .starter,
            title: "Unlock load-based targets",
            action: "Run an Estimated 1RM test on your main lifts so the coach can prescribe specific loads.",
            detail: "The coach needs your baseline strength to prescribe percentage-based loads. Without it, recommendations are general. A quick test on your top lifts gives the engine the data to produce specific set/rep/load targets.",
            citation: CitationRegistry.oneRMEstimation,
            confidence: .low,
            priority: 50)]
    }
}

/// Small numeric helpers shared by the prescriptive rules.
enum PrescriptionMath {
    /// Rounds a prescribed load to the nearest loadable increment (default 2.5 kg).
    static func roundLoad(_ kg: Double, increment: Double = KnowledgeBase.loadIncrementKg) -> Double {
        guard increment > 0 else { return kg }
        return (kg / increment).rounded() * increment
    }

    /// Set counts: integers render clean, halves keep one decimal ("8", "8.5").
    static func sets(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }
}
