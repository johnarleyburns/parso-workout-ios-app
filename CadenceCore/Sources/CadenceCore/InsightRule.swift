import Foundation

/// One forward-chaining rule: given the user's `TrainingFacts`, emit zero or more
/// read-only `Insight`s. Pure and isolated so each is individually testable (§03).
/// `priority` breaks ties within a severity band (higher first).
public struct InsightRule: Sendable {
    public let id: String
    public let priority: Int
    public let produce: @Sendable (TrainingFacts) -> [Insight]

    public init(id: String, priority: Int, produce: @escaping @Sendable (TrainingFacts) -> [Insight]) {
        self.id = id
        self.priority = priority
        self.produce = produce
    }
}

/// The bundled P3 rule set — the read-only slice of the Scientific Expert Engine.
/// Each rule cites published work (`CitationRegistry`); conservative, non-medical
/// framing throughout (D6).
public enum KnowledgeBase {

    public static let p3Rules: [InsightRule] = [
        volumeVsLandmarks,
        e1RMTrend,
        frequency,
        intensityVsGoal,
    ]

    /// P4 assessment rules — they reason over `TrainingFacts.assessments`.
    public static let p4Rules: [InsightRule] = [
        assessmentProgress,
        assessmentRetest,
    ]

    /// P6 cardio assessment rules — mirror p4Rules but for cardio kinds, with
    /// cardio-specific citations.
    public static let p6InsightRules: [InsightRule] = [
        cardioAssessmentProgress,
        cardioAssessmentRetest,
    ]

    /// Every active rule, run by the engine.
    public static let activeRules: [InsightRule] = p3Rules + p4Rules + p6InsightRules

    // MARK: - Rule 1: weekly volume vs MEV/MAV/MRV landmarks

    static let volumeVsLandmarks = InsightRule(id: "volume", priority: 100) { facts in
        var out: [Insight] = []
        for part in BodyPart.allCases {
            guard let sets = facts.weeklySetsByPart[part], sets > 0 else { continue }
            let bands = VolumeLandmarks.bands(for: part, experience: facts.experience)
            let zone = VolumeLandmarks.zone(sets: sets, for: part, experience: facts.experience)
            let name = part.displayName
            let setsText = Format.sets(sets)
            switch zone {
            case .belowMEV:
                out.append(Insight(
                    id: "volume.\(part.rawValue)",
                    kind: .volume, part: part,
                    title: "\(name) volume is low",
                    message: "\(name): \(setsText) sets this week — below the minimum effective volume (~\(Format.sets(bands.mev))).",
                    detail: "Meta-analyses show a dose-response between weekly sets per muscle and growth, with a threshold below which there's little adaptation. \(name) is under ~\(Format.sets(bands.mev)) working sets for your experience level; adding a set or two per session would land it in the productive range (~\(Format.sets(bands.mev))–\(Format.sets(bands.mav))).",
                    citation: CitationRegistry.volumeDoseResponse,
                    severity: .attention))
            case .productive:
                out.append(Insight(
                    id: "volume.\(part.rawValue)",
                    kind: .volume, part: part,
                    title: "\(name) volume is on track",
                    message: "\(name): \(setsText) sets this week — in the productive range.",
                    detail: "\(name) sits between its minimum effective (~\(Format.sets(bands.mev))) and maximum adaptive (~\(Format.sets(bands.mav))) weekly volume for your experience level — a good place to keep progressing.",
                    citation: CitationRegistry.volumeDoseResponse,
                    severity: .info))
            case .approachingMRV:
                out.append(Insight(
                    id: "volume.\(part.rawValue)",
                    kind: .volume, part: part,
                    title: "\(name) volume is high",
                    message: "\(name): \(setsText) sets this week — approaching the high end.",
                    detail: "\(name) is between its maximum adaptive (~\(Format.sets(bands.mav))) and maximum recoverable (~\(Format.sets(bands.mrv))) weekly volume. Productive, but watch recovery and session quality before adding more.",
                    citation: CitationRegistry.volumeDoseResponse,
                    severity: .info))
            case .overMRV:
                out.append(Insight(
                    id: "volume.\(part.rawValue)",
                    kind: .volume, part: part,
                    title: "\(name) volume may be too high",
                    message: "\(name): \(setsText) sets this week — over the recoverable range.",
                    detail: "\(name) is at or above its estimated maximum recoverable volume (~\(Format.sets(bands.mrv)) sets/week). When volume outpaces recovery, more sets stop paying off; consider holding or a lighter week.",
                    citation: CitationRegistry.volumeDoseResponse,
                    severity: .attention))
            }
        }
        return out
    }

    // MARK: - Rule 2: estimated-1RM trend per lift

    static let e1RMTrend = InsightRule(id: "trend", priority: 90) { facts in
        var out: [Insight] = []
        for (lift, direction) in facts.e1RMTrendByExercise {
            switch direction {
            case .declining:
                out.append(Insight(
                    id: "trend.\(lift)",
                    kind: .trend, exercise: lift,
                    title: "\(lift) is trending down",
                    message: "\(lift): estimated 1RM is lower than the prior week.",
                    detail: "Your best estimated 1RM on \(lift) (from logged load × reps) has dropped versus last week. A short-term dip is normal, but a sustained decline can signal accumulated fatigue or too little recovery — worth watching.",
                    citation: CitationRegistry.schoenfeld2021,
                    severity: .attention))
            case .flat:
                out.append(Insight(
                    id: "trend.\(lift)",
                    kind: .trend, exercise: lift,
                    title: "\(lift) has stalled",
                    message: "\(lift): estimated 1RM is flat versus last week.",
                    detail: "Your estimated 1RM on \(lift) is roughly unchanged. Progressive overload — adding reps within your range, then load — is what drives strength over time; a plateau is the cue to nudge one of them up.",
                    citation: CitationRegistry.schoenfeld2021,
                    severity: .info))
            case .rising:
                out.append(Insight(
                    id: "trend.\(lift)",
                    kind: .trend, exercise: lift,
                    title: "\(lift) is progressing",
                    message: "\(lift): estimated 1RM is up versus last week — nice work.",
                    detail: "Your best estimated 1RM on \(lift) rose versus last week. That's progressive overload working; keep the progression going while it holds.",
                    citation: CitationRegistry.schoenfeld2021,
                    severity: .info))
            }
        }
        return out
    }

    // MARK: - Rule 3: frequency (split volume across ≥2 sessions/week)

    static let frequency = InsightRule(id: "frequency", priority: 80) { facts in
        var out: [Insight] = []
        for part in BodyPart.allCases {
            guard let sets = facts.weeklySetsByPart[part], sets > 0,
                  let days = facts.frequencyByPart[part], days == 1 else { continue }
            let bands = VolumeLandmarks.bands(for: part, experience: facts.experience)
            // Only worth flagging once there's meaningful volume to split.
            guard sets >= bands.mev else { continue }
            let name = part.displayName
            out.append(Insight(
                id: "frequency.\(part.rawValue)",
                kind: .frequency, part: part,
                title: "Split your \(name.lowercased()) volume",
                message: "\(name): \(Format.sets(sets)) sets in a single day this week.",
                detail: "When weekly volume is high, spreading it across two or more sessions tends to produce at least as much growth as cramming it into one — likely through better per-set quality. Consider training \(name.lowercased()) on a second day.",
                citation: CitationRegistry.frequencyMeta,
                severity: .info))
        }
        return out
    }

    // MARK: - Rule 4: intensity distribution vs goal

    static let intensityVsGoal = InsightRule(id: "intensity", priority: 70) { facts in
        let dist = facts.intensity
        guard dist.sampleCount > 0 else { return [] }
        switch facts.goal {
        case .strength:
            guard dist.heavy < 0.34 else { return [] }
            return [Insight(
                id: "intensity.strength",
                kind: .intensity,
                title: "Lift heavier for strength",
                message: "Most of your sets are lighter than ~80% 1RM.",
                detail: "For a strength goal there's a clear dose-response favouring heavy loads: roughly 1–5 reps at ~80–100% of 1RM best builds maximal strength. Only \(Format.percent(dist.heavy)) of your loaded sets this week were in that heavy range.",
                citation: CitationRegistry.schoenfeld2021,
                severity: .attention)]
        case .endurance:
            guard dist.heavy > 0.5 else { return [] }
            return [Insight(
                id: "intensity.endurance",
                kind: .intensity,
                title: "Lighter loads suit endurance",
                message: "Your sets skew heavy for an endurance goal.",
                detail: "Local muscular endurance tends to favour higher reps at lighter loads, though the evidence here is more equivocal than for strength or hypertrophy — treat this as a lower-confidence nudge. \(Format.percent(dist.heavy)) of your loaded sets this week were heavy (≥80% 1RM).",
                citation: CitationRegistry.schoenfeld2021,
                severity: .info)]
        case .hypertrophy:
            // For hypertrophy, proximity-to-failure (RIR), not load, is the primary
            // driver — flag only when sets look far from failure.
            guard let rir = facts.avgRIR, rir > 4 else { return [] }
            return [Insight(
                id: "intensity.hypertrophy",
                kind: .intensity,
                title: "Train closer to failure",
                message: "Your sets average about \(Format.oneDecimal(rir)) reps in reserve.",
                detail: "For hypertrophy, growth is similar across a wide load range as long as sets are taken near failure — proximity to failure, not the load itself, is the main driver. Averaging ~\(Format.oneDecimal(rir)) RIR suggests leaving several reps in the tank; pushing closer (0–3 RIR) would likely add stimulus.",
                citation: CitationRegistry.schoenfeld2021,
                severity: .info)]
        }
    }

    // MARK: - Rule 5: assessment progress (longitudinal test deltas)

    static let assessmentProgress = InsightRule(id: "assessment.progress", priority: 95) { facts in
        var out: [Insight] = []
        for s in facts.assessments {
            // Need at least a baseline + a re-test to talk about change.
            guard s.count >= 2 else { continue }
            let label = AssessmentFormat.seriesLabel(s)
            let change = AssessmentFormat.change(s)
            let cite = s.kind.category == .strength
                ? CitationRegistry.oneRMEstimation
                : CitationRegistry.schoenfeld2021
            switch s.trend {
            case .improved:
                out.append(Insight(
                    id: "assessment.\(s.id)",
                    kind: .assessment, exercise: s.exerciseName,
                    title: "\(label) is improving",
                    message: "\(label): \(change) since your first test.",
                    detail: "Re-testing the same standardized protocol is how you separate real progress from day-to-day noise. Your \(label.lowercased()) is up \(change) versus baseline — beyond the margin we'd write off as measurement error — so the training is working. Keep the block going, then re-test.",
                    citation: cite,
                    severity: .info))
            case .declined:
                out.append(Insight(
                    id: "assessment.\(s.id)",
                    kind: .assessment, exercise: s.exerciseName,
                    title: "\(label) has dropped",
                    message: "\(label): \(change) since your first test.",
                    detail: "Your \(label.lowercased()) has fallen \(change) versus baseline — past what measurement noise alone explains. A single dip can be fatigue or a bad test day, but a real decline is a cue to check recovery, then re-test before changing the plan.",
                    citation: cite,
                    severity: .attention))
            case .unchanged, .single:
                continue
            }
        }
        return out
    }

    // MARK: - Rule 6: re-test cadence (block-end reminder, D5)

    static let assessmentRetest = InsightRule(id: "assessment.retest", priority: 60) { facts in
        facts.assessmentsDueForRetest.map { s in
            let label = AssessmentFormat.seriesLabel(s)
            return Insight(
                id: "assessment.retest.\(s.id)",
                kind: .assessment, exercise: s.exerciseName,
                title: "Time to re-test \(label.lowercased())",
                message: "It's been over six weeks since your last \(label.lowercased()) test.",
                detail: "Assessments are most useful as a pre/post pair: test, train a block, then re-test on the same protocol to measure the change. It's been a full training block (~6–8 weeks) since you last tested \(label.lowercased()) — a good time to re-run it and see where you stand.",
                citation: CitationRegistry.schoenfeld2021,
                severity: .info)
        }
    }

    // MARK: - P6 rules: cardio assessment progress + retest

    /// Cardio assessment progress — mirrors `assessmentProgress` but only for
    /// cardio kinds (VO₂max / Wingate), with cardio-specific citations.
    static let cardioAssessmentProgress = InsightRule(id: "assessment.cardio.progress", priority: 94) { facts in
        var out: [Insight] = []
        for s in facts.assessments where s.kind.category == .cardio {
            guard s.count >= 2 else { continue }
            let label = AssessmentFormat.seriesLabel(s)
            let change = AssessmentFormat.change(s)
            let cite = s.kind == .wingate
                ? CitationRegistry.wingateTest
                : CitationRegistry.cooperVo2max
            switch s.trend {
            case .improved:
                out.append(Insight(
                    id: "assessment.cardio.\(s.id)",
                    kind: .assessment,
                    title: "\(label) is improving",
                    message: "\(label): \(change) since your baseline.",
                    detail: "Your \(label.lowercased()) is up \(change) versus baseline — beyond what measurement noise would explain. The current training block is working; keep it going and re-test at the end of the next cycle.",
                    citation: cite,
                    severity: .info))
            case .declined:
                out.append(Insight(
                    id: "assessment.cardio.\(s.id)",
                    kind: .assessment,
                    title: "\(label) has dropped",
                    message: "\(label): \(change) since your baseline.",
                    detail: "Your \(label.lowercased()) has fallen \(change) versus baseline — past what measurement noise alone explains. A single dip can be fatigue or a bad test day, but a decline over two tests is a cue to check your conditioning focus.",
                    citation: cite,
                    severity: .attention))
            case .unchanged, .single: continue
            }
        }
        return out
    }

    /// Cardio re-test cadence — mirrors `assessmentRetest` for cardio kinds.
    static let cardioAssessmentRetest = InsightRule(id: "assessment.cardio.retest", priority: 59) { facts in
        facts.assessmentsDueForRetest
            .filter { $0.kind.category == .cardio }
            .map { s in
                let label = AssessmentFormat.seriesLabel(s)
                return Insight(
                    id: "assessment.cardio.retest.\(s.id)",
                    kind: .assessment,
                    title: "Time to re-test \(label.lowercased())",
                    message: "It's been over six weeks since your last \(label.lowercased()) test.",
                    detail: "Assessments work best as a pre/post pair. It's been a full training block (~6–8 weeks) since your last \(label.lowercased()) — a good time to re-run it and see where you stand.",
                    citation: CitationRegistry.schoenfeld2021,
                    severity: .info)
            }
    }
}

/// Formatting for assessment insights — unit-aware values and labels.
enum AssessmentFormat {
    /// A human label for a series, e.g. "Bench press 1RM" or "Max push-ups".
    static func seriesLabel(_ s: AssessmentSummary) -> String {
        if s.kind.concernsLift, let lift = s.exerciseName, !lift.isEmpty {
            switch s.kind {
            case .e1RM:  return "\(lift) 1RM"
            case .repMax: return "\(lift) rep-max"
            default: return s.kind.displayName
            }
        }
        return s.kind.displayName
    }

    /// The baseline→latest change, signed and unit-aware ("+12 reps", "−4 kg",
    /// "+8 s"). Weight renders in kilograms (the engine's canonical unit).
    static func change(_ s: AssessmentSummary) -> String {
        let d = s.delta
        let sign = d >= 0 ? "+" : "−"
        let mag = abs(d)
        switch s.kind.unit {
        case .weightKg: return "\(sign)\(Format.sets((mag * 10).rounded() / 10)) kg"
        case .reps:     return "\(sign)\(Int(mag.rounded())) reps"
        case .seconds:  return "\(sign)\(Int(mag.rounded())) s"
        case .mlKgMin:  return "\(sign)\(String(format: "%.1f", mag)) mL/kg/min"
        case .watts:    return "\(sign)\(Int(mag.rounded())) W"
        }
    }
}

/// Small number formatting helpers shared by the rules.
enum Format {
    /// Set counts: integers render clean, halves keep one decimal ("4", "4.5").
    static func sets(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }
    static func oneDecimal(_ value: Double) -> String { String(format: "%.1f", value) }
    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
}
