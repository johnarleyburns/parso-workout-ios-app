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

    /// P6 cardio rules — prescribe aerobic work. Conservative: beginners get
    /// moderate work before harder interval prescriptions.
    static let p6RecRules: [RecommendationRule] = [
        cardioModerate,
        cardioHIIT,
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
                        let incrementLoad = PrescriptionMath.roundLoad(snap.topSetWeightKg + loadIncrementKg)
                        let nextLoad = min(goalLoad, incrementLoad)
                        target = SetTarget(sets: nil, repsLow: range.lowerBound, repsHigh: range.lowerBound,
                                           loadKg: nextLoad, rir: rir)
                        action = "Your assessed 1RM supports building load, but keep the jump conservative — try \(SetTarget.trimmed(nextLoad)) kg and reassess from there."
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
                    let nextLoad = goalLoad > snap.topSetWeightKg ? min(goalLoad, incrementLoad) : incrementLoad
                    target = SetTarget(sets: nil, repsLow: range.lowerBound, repsHigh: range.lowerBound,
                                       loadKg: nextLoad, rir: rir)
                    action = "You hit \(range.upperBound) reps — add a small load jump to \(SetTarget.trimmed(nextLoad)) kg and reset to \(range.lowerBound)."
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
                detail: "Progressive overload drives strength and size: within a rep range, add reps to the top of the range first, then add load and reset — autoregulated by reps in reserve (RIR). Your \(facts.goal.displayName.lowercased()) range is \(range.lowerBound)–\(range.upperBound) reps at about \(rir) RIR.\(assessedE1RM != nil ? " Your assessed 1RM informs the load, but Coach still limits the jump so the next session confirms it." : "")",
                citation: CitationRegistry.rpeAutoregulation,
                citationIds: assessedE1RM != nil ? ["oneRMEstimation", "currierResistancePrescription2023"] : ["currierResistancePrescription2023"],
                target: target,
                confidence: confidence,
                priority: 100))
        }
        return out
    }

    // MARK: - Rule: flag a declining estimated 1RM for monitoring

    /// A single-week e1RM decline may be noise (sleep, technique, order, measurement
    /// error). This rule flags it at lower confidence for monitoring; it does not
    /// automatically prescribe a deload unless corroborated by repeated decline or
    /// concurrent poor readiness. Priority is below progression so a declining lift
    /// can still progress if the user feels ready.
    static let deload = RecommendationRule(id: "deload", priority: 95) { facts in
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
                title: "\(lift) trending down — monitor recovery",
                action: "Your estimated 1RM is slightly lower this week. This could be fatigue, or it could be noise. If it drops again next week, take a lighter session.",
                detail: "A single-week decline can be normal variation — sleep, exercise order, technique, and measurement noise can all cause it. Coach flags this for monitoring. A deload is suggested only if the decline repeats or readiness is poor. This is a coaching cue, not a medical one.",
                citation: CitationRegistry.rpeAutoregulation,
                target: target,
                confidence: .low,
                priority: 95))
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
                action: "\(name): \(Format.progress(done: current, target: bands.mev, unit: "sets")) this week. Add ~\(toAdd) set\(toAdd == 1 ? "" : "s") to start closing it.",
                detail: "Weekly sets per muscle drive growth in a graded dose-response, but the exact useful dose varies by person. \(name) is on the low side of the starting range for your experience level (~\(PrescriptionMath.sets(bands.mev)) sets/week); add a couple of sets, then judge by performance and recovery.",
                citation: CitationRegistry.volumeDoseResponse,
                target: SetTarget(sets: toAdd, repsLow: range.lowerBound, repsHigh: range.upperBound,
                                  loadKg: nil, rir: rir),
                confidence: .moderate,
                priority: 90))
        }
        return out
    }

    /// The cold-start prescription: alternating full-body A/B sessions derived from
    /// the user's goal + experience. Replaces the old squat-bench-deadlift prescription
    /// with a balanced pattern-based starter informed by ACSM 2026 guidelines.
    static func starter(goal: TrainingGoal, experience: ExperienceLevel) -> Recommendation {
        let range = goal.repRange
        let rir = goal.targetRIR
        return Recommendation(
            id: "starter",
            kind: .starter,
            title: "Start with a full-body session",
            action: "New here? Try alternating full-body sessions: Session A (squat, push, pull, carry) and Session B (hinge, press, pull, core). 2–3 sets per movement, \(range.lowerBound)–\(range.upperBound) reps, leaving ~\(rir) in reserve.",
            detail: "With no history yet, alternating full-body sessions are a well-supported starting point informed by dose-response meta-analyses. This approach trains each muscle often, keeps volume manageable, and gives the coach data to work from. Log a few sessions and the recommendations get specific to your lifts.",
            citation: CitationRegistry.schoenfeld2021,
            target: SetTarget(sets: 3, repsLow: range.lowerBound, repsHigh: range.upperBound, loadKg: nil, rir: rir),
            confidence: .moderate,
            priority: 0)
    }

    // MARK: - P6: aerobic prescriptions (recovery-aware redesign)

    /// Conservative aerobic starter: beginners and inactive users get moderate
    /// continuous work, not HIIT. Reserved HIIT for users with an established base.
    private static let vo2maxKinds: Set<AssessmentKind> = [.vo2maxField, .cooper12min, .run1_5mile, .rockportWalk, .queensCollegeStep]

    /// General aerobic recommendation: 150 min/week moderate-equivalent floor.
    /// Low priority so it surfaces only when nothing higher-priority is relevant.
    static let cardioModerate = RecommendationRule(id: "cardio.moderate", priority: 70) { facts in
        guard facts.totalWorkingSets >= 3 else { return [] }
        let action = facts.experience == .beginner
            ? "Build your aerobic base: try 20–30 min of moderate work (brisk walk, light cycle, or easy swim) 2–3 times a week. Progress duration before intensity."
            : "Accumulate moderate aerobic work toward the 150 min/week floor: brisk walking, easy cycling, swimming, or any steady-effort activity."
        return [Recommendation(
            id: "cardio.moderate",
            kind: .starter,
            title: "Build your aerobic fitness",
            action: action,
            detail: "A harmonised meta-analysis of over 1 million adults found a graded dose-response between physical activity volume and reduced mortality. Coach starts you with tolerable moderate work and progresses from adherence — no aggressive HIIT prescription without an established base.",
            citation: CitationRegistry.ekelundActivityMortality2016,
            confidence: .moderate,
            priority: 70)]
    }

    /// When VO₂max is declining AND the user has an established training base,
    /// prescribe interval training as ONE option (not the universal default).
    /// Beginners and inactive users are excluded — they get moderate work instead.
    static let cardioHIIT = RecommendationRule(id: "cardio.hiit", priority: 75) { facts in
        guard facts.experience != .beginner else { return [] }
        var out: [Recommendation] = []
        for s in facts.assessments where vo2maxKinds.contains(s.kind) && s.trend == .declined {
            let label = AssessmentFormat.seriesLabel(s)
            out.append(Recommendation(
                id: "cardio.hiit.vo2max",
                kind: .cardioHIIT,
                title: "Boost your aerobic fitness",
                action: "Consider interval work: options include a Norwegian 4×4 session (4×4 min hard / 3 min recovery) or shorter long-interval protocols, paired with your usual training.",
                detail: "High-intensity intervals can improve VO₂max, but they are one option among many. Your \(label.lowercased()) is declining. If recovery and preference support it, 1–2 interval sessions/week can help. Moderate continuous work remains effective and may be more sustainable.",
                citation: CitationRegistry.crowleyVO2Intensity2022,
                citationIds: ["poonHIIT2024"],
                cardioPrescription: "Long intervals (e.g. 4×4)",
                confidence: .moderate,
                priority: 75))
        }
        return out
    }

    /// Legacy P6 strength-card rules no longer prescribe SIT here; the richer
    /// coach decision engine handles hard sprint work with recovery and preference
    /// gates.
    static let cardioSIT = RecommendationRule(id: "cardio.sit", priority: 0) { _ in [] }

    // MARK: - Rule: prompt to run missing assessments (FR-12.3)

    static let missingBaseline = RecommendationRule(id: "missingBaseline", priority: 50) { facts in
        guard !facts.hasAnyAssessment else { return [] }
        guard facts.totalWorkingSets >= 3 else { return [] }
        return [Recommendation(
            id: "missingBaseline.strength",
            kind: .starter,
            title: "Add a strength test baseline",
            action: "Run an Estimated 1RM test on your main lifts so the coach can prescribe specific loads.",
            detail: "Your logged workouts are enough for habit, volume, and lift-history trends. A separate e1RM or rep-max test gives Coach a measured strength baseline for percentage-based load targets.",
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
