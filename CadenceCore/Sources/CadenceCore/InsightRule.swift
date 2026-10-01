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
        incompleteCustomExercises,
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

    /// The muscle groups a per-group insight may speak about, in canonical order:
    /// the groups the coach programs by default, plus any other group the user has
    /// actually trained this week. An untracked group with no volume is silent —
    /// the catalog cannot satisfy a weekly target for it (decision D4), so nagging
    /// about it would be advice the user cannot act on.
    static func surfacedGroups(_ facts: TrainingFacts) -> [MuscleGroup] {
        MuscleGroup.canonicalOrder.filter {
            $0.isTrackedByDefault || (facts.weeklySetsByGroup[$0] ?? 0) > 0
        }
    }

    // MARK: - Rule 1: weekly volume vs evidence-informed starting ranges

    static let volumeVsLandmarks = InsightRule(id: "volume", priority: 100) { facts in
        var out: [Insight] = []
        for group in KnowledgeBase.surfacedGroups(facts) {
            let name = group.displayName
            let bands = VolumeLandmarks.bands(for: group, experience: facts.experience)
            guard let sets = facts.weeklySetsByGroup[group], sets > 0 else {
                // No training volume for this muscle group this week. Surface it so
                // the user can tell the difference between "biceps is on track" and
                // "biceps was never trained and may need attention." (Feedback:
                // end-of-week silence on untrained groups left users uncertain.)
                out.append(Insight(
                    id: "volume.\(group.rawValue)",
                    kind: .volume, group: group,
                    title: String(localized: "\(name) volume is low", bundle: .module),
                    message: String(localized: "\(name): \(Format.progress(done: 0, target: bands.mev, unit: "sets")) this week to reach Coach's starting range.", bundle: .module),
                    detail: String(localized: "\(name) has not been trained this week. Meta-analyses show a graded dose-response between weekly sets per muscle and growth; Coach's starting range is ~\(Format.sets(bands.mev))–\(Format.sets(bands.mav)) sets/week for your experience. This may be intentional (a rest week or a focused block), but if it isn't, add 1–2 sets and adjust by feel and performance.", bundle: .module),
                    citation: CitationRegistry.volumeDoseResponse,
                    severity: .attention))
                continue
            }
            let zone = VolumeLandmarks.zone(sets: sets, for: group, experience: facts.experience)
            let setsText = Format.sets(sets)
            switch zone {
            case .belowMEV:
                out.append(Insight(
                    id: "volume.\(group.rawValue)",
                    kind: .volume, group: group,
                    title: String(localized: "\(name) volume is low", bundle: .module),
                    message: String(localized: "\(name): \(Format.progress(done: sets, target: bands.mev, unit: "sets")) this week to reach the starting range.", bundle: .module),
                    detail: String(localized: "Meta-analyses show a graded dose-response between weekly sets per muscle and growth, but the exact useful dose varies by person. \(name) is below Coach's starting range (~\(Format.sets(bands.mev))–\(Format.sets(bands.mav)) sets/week); add a set or two and judge by performance and recovery.", bundle: .module),
                    citation: CitationRegistry.volumeDoseResponse,
                    severity: .attention))
            case .productive:
                // Being within a productive range is not a useful coach
                // suggestion. Keep the fact available to volume dashboards,
                // but do not create Home-card noise for it.
                break
            case .approachingMRV:
                out.append(Insight(
                    id: "volume.\(group.rawValue)",
                    kind: .volume, group: group,
                    title: String(localized: "\(name) volume is high", bundle: .module),
                    message: String(localized: "\(name): \(setsText) sets this week — approaching the high end.", bundle: .module),
                    detail: String(localized: "\(name) is above Coach's starting range and approaching the high end (~\(Format.sets(bands.mrv)) sets/week). It may still be useful if performance is improving, but watch recovery and session quality before adding more.", bundle: .module),
                    citation: CitationRegistry.volumeDoseResponse,
                    severity: .info))
            case .overMRV:
                out.append(Insight(
                    id: "volume.\(group.rawValue)",
                    kind: .volume, group: group,
                    title: String(localized: "\(name) volume may be too high", bundle: .module),
                    message: String(localized: "\(name): \(setsText)/\(Format.sets(bands.mrv)) sets this week · \(Format.sets(sets - bands.mrv)) over the high end.", bundle: .module),
                    detail: String(localized: "\(name) is above Coach's high-end starting point (~\(Format.sets(bands.mrv)) sets/week). More sets have diminishing returns and only help if you recover from them; consider holding or taking a lighter week.", bundle: .module),
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
                    detail: String(localized: "Your best estimated 1RM on \(lift) (from logged load × reps) has dropped versus last week. A short-term dip is normal, but a sustained decline can signal accumulated fatigue or too little recovery — worth watching.", bundle: .module),
                    citation: CitationRegistry.schoenfeld2021,
                    severity: .attention))
            case .flat:
                out.append(Insight(
                    id: "trend.\(lift)",
                    kind: .trend, exercise: lift,
                    title: String(localized: "\(lift) has stalled", bundle: .module),
                    message: "\(lift): estimated 1RM is flat versus last week.",
                    detail: String(localized: "Your estimated 1RM on \(lift) is roughly unchanged. Progressive overload — adding reps within your range, then load — is what drives strength over time; a plateau is the cue to nudge one of them up.", bundle: .module),
                    citation: CitationRegistry.schoenfeld2021,
                    severity: .info))
            case .rising:
                out.append(Insight(
                    id: "trend.\(lift)",
                    kind: .trend, exercise: lift,
                    title: "\(lift) is progressing",
                    message: "\(lift): estimated 1RM is up versus last week — nice work.",
                    detail: String(localized: "Your best estimated 1RM on \(lift) rose versus last week. That's progressive overload working; keep the progression going while it holds.", bundle: .module),
                    citation: CitationRegistry.schoenfeld2021,
                    severity: .info))
            }
        }
        return out
    }

    // MARK: - Rule 3: frequency (split volume across ≥2 sessions/week)

    static let frequency = InsightRule(id: "frequency", priority: 80) { facts in
        var out: [Insight] = []
        for group in KnowledgeBase.surfacedGroups(facts) {
            guard let sets = facts.weeklySetsByGroup[group], sets > 0,
                  let days = facts.frequencyByGroup[group], days == 1 else { continue }
            let bands = VolumeLandmarks.bands(for: group, experience: facts.experience)
            // Only worth flagging once there's meaningful volume to split.
            guard sets >= bands.mev else { continue }
            let name = group.displayName
            out.append(Insight(
                id: "frequency.\(group.rawValue)",
                kind: .frequency, group: group,
                title: String(localized: "Split your \(name.lowercased()) volume", bundle: .module),
                message: String(localized: "\(name): \(Format.sets(sets)) sets in a single day this week.", bundle: .module),
                detail: String(localized: "When weekly volume is high, spreading it across two or more sessions tends to produce at least as much growth as cramming it into one — likely through better per-set quality. Consider training \(name.lowercased()) on a second day.", bundle: .module),
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
                title: String(localized: "Lift heavier for strength", bundle: .module),
                message: String(localized: "Most of your sets are lighter than ~80% 1RM.", bundle: .module),
                detail: String(localized: "For a strength goal there's a clear dose-response favouring heavy loads: roughly 1–5 reps at ~80–100% of 1RM best builds maximal strength. Only \(Format.percent(dist.heavy)) of your loaded sets this week were in that heavy range.", bundle: .module),
                citation: CitationRegistry.schoenfeld2021,
                severity: .attention)]
        case .endurance:
            guard dist.heavy > 0.5 else { return [] }
            return [Insight(
                id: "intensity.endurance",
                kind: .intensity,
                title: String(localized: "Lighter loads suit endurance", bundle: .module),
                message: String(localized: "Your sets skew heavy for an endurance goal.", bundle: .module),
                detail: String(localized: "Local muscular endurance tends to favour higher reps at lighter loads, though the evidence here is more equivocal than for strength or hypertrophy — treat this as a lower-confidence nudge. \(Format.percent(dist.heavy)) of your loaded sets this week were heavy (≥80% 1RM).", bundle: .module),
                citation: CitationRegistry.schoenfeld2021,
                severity: .info)]
        case .hypertrophy:
            // For hypertrophy, proximity-to-failure (RIR), not load, is the primary
            // driver — flag only when sets look far from failure.
            guard let rir = facts.avgRIR, rir > 4 else { return [] }
            return [Insight(
                id: "intensity.hypertrophy",
                kind: .intensity,
                title: String(localized: "Train closer to failure", bundle: .module),
                message: String(localized: "Your sets average about \(Format.oneDecimal(rir)) reps in reserve.", bundle: .module),
                detail: String(localized: "For hypertrophy, growth is similar across a wide load range as long as sets are taken near failure — proximity to failure, not the load itself, is the main driver. Averaging ~\(Format.oneDecimal(rir)) RIR suggests leaving several reps in the tank; pushing closer (0–3 RIR) would likely add stimulus.", bundle: .module),
                citation: CitationRegistry.schoenfeld2021,
                severity: .info)]
        }
    }

    // MARK: - Rule 5: incomplete custom exercises

    static let incompleteCustomExercises = InsightRule(
        id: "incompleteCustomExercises",
        priority: 105,
        produce: { facts in
            guard !facts.incompleteCustomExerciseNames.isEmpty else { return [] }
            let names = facts.incompleteCustomExerciseNames
            let count = names.count
            let examples = names.prefix(3).map { "'\($0)'" }.joined(separator: ", ")
            let message = count == 1
                ? "\(examples) is missing muscle data — the coach can't track volume for it."
                : String(localized: "\(count) exercises (\(examples)) are missing muscle data — the coach can't track volume for them.", bundle: .module)
            return [Insight(
                id: "exerciseDefinition.incomplete",
                kind: .exerciseDefinition,
                title: String(localized: "Custom exercises need muscle definitions", bundle: .module),
                message: message,
                detail: String(localized: "Accurate exercise classification is essential for quantifying training loads and informing programming decisions (Brennan et al., 2025). Tap to open Custom Exercises in Settings to edit or merge them.", bundle: .module),
                citation: CitationRegistry.citation(forId: "brennanExerciseClassification2025") ?? CitationRegistry.schoenfeld2021,
                severity: .attention)]
        }
    )

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
                    message: String(localized: "\(label): \(change) since your first test.", bundle: .module),
                    detail: String(localized: "Re-testing the same standardized protocol is how you separate real progress from day-to-day noise. Your \(label.lowercased()) is up \(change) versus baseline — beyond the margin we'd write off as measurement error — so the training is working. Keep the block going, then re-test.", bundle: .module),
                    citation: cite,
                    severity: .info))
            case .declined:
                out.append(Insight(
                    id: "assessment.\(s.id)",
                    kind: .assessment, exercise: s.exerciseName,
                    title: String(localized: "\(label) has dropped", bundle: .module),
                    message: String(localized: "\(label): \(change) since your first test.", bundle: .module),
                    detail: String(localized: "Your \(label.lowercased()) has fallen \(change) versus baseline — past what measurement noise alone explains. A single dip can be fatigue or a bad test day, but a real decline is a cue to check recovery, then re-test before changing the plan.", bundle: .module),
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
                title: String(localized: "Time to re-test \(label.lowercased())", bundle: .module),
                message: String(localized: "It's been over six weeks since your last \(label.lowercased()) test.", bundle: .module),
                detail: String(localized: "Assessments are most useful as a pre/post pair: test, train a block, then re-test on the same protocol to measure the change. It's been a full training block (~6–8 weeks) since you last tested \(label.lowercased()) — a good time to re-run it and see where you stand.", bundle: .module),
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
                    message: String(localized: "\(label): \(change) since your baseline.", bundle: .module),
                    detail: String(localized: "Your \(label.lowercased()) is up \(change) versus baseline — beyond what measurement noise would explain. The current training block is working; keep it going and re-test at the end of the next cycle.", bundle: .module),
                    citation: cite,
                    severity: .info))
            case .declined:
                out.append(Insight(
                    id: "assessment.cardio.\(s.id)",
                    kind: .assessment,
                    title: String(localized: "\(label) has dropped", bundle: .module),
                    message: String(localized: "\(label): \(change) since your baseline.", bundle: .module),
                    detail: String(localized: "Your \(label.lowercased()) has fallen \(change) versus baseline — past what measurement noise alone explains. A single dip can be fatigue or a bad test day, but a decline over two tests is a cue to check your conditioning focus.", bundle: .module),
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
                    title: String(localized: "Time to re-test \(label.lowercased())", bundle: .module),
                    message: String(localized: "It's been over six weeks since your last \(label.lowercased()) test.", bundle: .module),
                    detail: String(localized: "Assessments work best as a pre/post pair. It's been a full training block (~6–8 weeks) since your last \(label.lowercased()) — a good time to re-run it and see where you stand.", bundle: .module),
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
            case .repMax: return String(localized: "\(lift) rep-max", bundle: .module)
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
        case .reps:     return String(localized: "\(sign)\(Int(mag.rounded())) reps", bundle: .module)
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

    /// Progress-bar style summary: "5/8 sets · 3 to go" (or "· target met" when
    /// done ≥ target). Gives the user a clear done-vs-remaining read at a glance.
    static func progress(done: Double, target: Double, unit: String) -> String {
        let remaining = max(0, target - done)
        let head = "\(sets(done))/\(sets(target)) \(unit)"
        return remaining > 0 ? "\(head) · \(sets(remaining)) to go" : "\(head) · target met"
    }
}
