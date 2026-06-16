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
