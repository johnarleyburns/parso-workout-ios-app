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

    // MARK: - Rule: double-progression for a lift that isn't declining

    static let progression = RecommendationRule(id: "progression", priority: 100) { facts in
        let range = facts.goal.repRange
        let rir = facts.goal.targetRIR
        var out: [Recommendation] = []
        for snap in facts.liftSnapshots.values where snap.topSetWeightKg > 0 {
            // Declining lifts are handled by the deload rule, not progressed.
            if snap.trend == .declining { continue }
            let confidence: RecommendationConfidence = snap.trend == .flat ? .high : .moderate
            let lift = snap.exercise
            let target: SetTarget
            let action: String
            if snap.topSetReps < range.upperBound {
                // Add a rep at the same load (top of double progression).
                let nextReps = snap.topSetReps + 1
                target = SetTarget(sets: nil, repsLow: nextReps, repsHigh: nextReps,
                                   loadKg: snap.topSetWeightKg, rir: rir)
                action = "Add a rep on your top set at the same load — keep going until you reach \(range.upperBound)."
            } else {
                // Hit the top of the range: add load and reset to the bottom.
                let nextLoad = PrescriptionMath.roundLoad(snap.topSetWeightKg + loadIncrementKg)
                target = SetTarget(sets: nil, repsLow: range.lowerBound, repsHigh: range.lowerBound,
                                   loadKg: nextLoad, rir: rir)
                action = "You hit \(range.upperBound) reps — add a little load and drop back to \(range.lowerBound)."
            }
            out.append(Recommendation(
                id: "progression.\(lift)",
                kind: .progression, part: snap.part, exercise: lift,
                title: "Progress your \(lift.lowercased())",
                action: action,
                detail: "Progressive overload drives strength and size: within a rep range, add reps to the top of the range first, then add load and reset — autoregulated by reps in reserve (RIR). Your \(facts.goal.displayName.lowercased()) range is \(range.lowerBound)–\(range.upperBound) reps at about \(rir) RIR.",
                citation: CitationRegistry.rpeAutoregulation,
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
            let toAdd = max(1, Int((bands.mev - current).rounded(.up)))
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
