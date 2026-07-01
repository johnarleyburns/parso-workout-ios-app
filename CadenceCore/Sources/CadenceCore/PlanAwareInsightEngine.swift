import Foundation

public struct PlanAwareWeeklyAccounting: Sendable, Equatable {
    public let completedSetsByPart: [BodyPart: Double]
    public let plannedRemainingSetsByPart: [BodyPart: Double]
    public let projectedSetsByPart: [BodyPart: Double]
    public let plannedStrengthSessionCount: Int

    public init(completed: TrainingFacts, plannedStrengthSessions: [CoachSession]) {
        self.completedSetsByPart = completed.weeklySetsByPart
        self.plannedRemainingSetsByPart = Self.plannedSetsByPart(from: plannedStrengthSessions)
        self.projectedSetsByPart = completed.weeklySetsByPart.merging(plannedRemainingSetsByPart) { $0 + $1 }
        self.plannedStrengthSessionCount = plannedStrengthSessions.filter { $0.kind == .strength }.count
    }

    public static func plannedSetsByPart(from sessions: [CoachSession]) -> [BodyPart: Double] {
        plannedSetsByPart(from: sessions.flatMap { session -> [CoachSession.RecommendedExercise] in
            guard session.kind == .strength else { return [] }
            return session.exercises ?? []
        })
    }

    public static func plannedSetsByPart(from exercises: [CoachSession.RecommendedExercise]) -> [BodyPart: Double] {
        var result: [BodyPart: Double] = [:]
        for exercise in exercises {
            let sets = Double(max(1, exercise.sets ?? 3))
            let muscles = muscleIDs(for: exercise)
            let primary = BodyPart.parts(forMuscleIDs: muscles.primary)
            let secondary = BodyPart.parts(forMuscleIDs: muscles.secondary).subtracting(primary)
            for part in primary {
                result[part, default: 0] += sets
            }
            for part in secondary {
                result[part, default: 0] += sets * TrainingFacts.secondaryWeight
            }
        }
        return result
    }

    private static func muscleIDs(for exercise: CoachSession.RecommendedExercise) -> (primary: [String], secondary: [String]) {
        if !exercise.primaryMuscles.isEmpty {
            return (exercise.primaryMuscles, [])
        }
        if let template = ExerciseLibrary.byName[exercise.name.lowercased()] {
            return (template.primaryMuscles, template.secondaryMuscles)
        }
        return ([], [])
    }
}

public enum PlanAwareInsightEngine {
    public static func run(completed facts: TrainingFacts,
                           plan: WeeklyPlan,
                           plannedStrengthSessions: [CoachSession],
                           unresolvedDeficits: [BodyPart: Double] = [:],
                           diagnostics: [PlanningDiagnostic] = [],
                           isBehindPlan: Bool = false,
                           now: Date = Date()) -> [Insight] {
        let base = InsightEngine.run(facts)
        guard base.first?.kind != .coldStart else { return base }

        let accounting = PlanAwareWeeklyAccounting(completed: facts,
                                                   plannedStrengthSessions: plannedStrengthSessions)
        guard accounting.plannedStrengthSessionCount > 0 else {
            guard !unresolvedDeficits.isEmpty else { return base }
            let unresolvedParts = Set(unresolvedDeficits.keys)
            let filtered = base.filter { insight in
                !(insight.kind == .volume
                  && insight.severity == .attention
                  && insight.title.localizedCaseInsensitiveContains("low")
                  && insight.part.map { unresolvedParts.contains($0) } == true)
            }
            return ranked(filtered + unresolvedPlanningInsights(deficits: unresolvedDeficits,
                                                                diagnostics: diagnostics,
                                                                experience: facts.experience))
        }

        let unresolvedParts = Set(unresolvedDeficits.keys)
        let filtered = base.compactMap { insight -> Insight? in
            guard insight.kind == .volume,
                  insight.severity == .attention,
                  let part = insight.part,
                  insight.title.localizedCaseInsensitiveContains("low") else {
                return insight
            }

            if unresolvedParts.contains(part) {
                return nil
            }

            let projectedSets = accounting.projectedSetsByPart[part] ?? 0
            let projectedZone = VolumeLandmarks.zone(sets: projectedSets,
                                                     for: part,
                                                     experience: facts.experience)
            guard projectedZone == .belowMEV else { return nil }

            let plannedSets = accounting.plannedRemainingSetsByPart[part] ?? 0
            guard plannedSets > 0 else { return insight }
            return projectedLowVolumeInsight(for: part,
                                             completedSets: accounting.completedSetsByPart[part] ?? 0,
                                             plannedSets: plannedSets,
                                             projectedSets: projectedSets,
                                             experience: facts.experience)
        }

        let behind = behindPlanInsights(facts: facts, accounting: accounting,
                                        isBehindPlan: isBehindPlan, plan: plan, now: now)
        let unresolved = unresolvedPlanningInsights(deficits: unresolvedDeficits,
                                                    diagnostics: diagnostics,
                                                    experience: facts.experience)
        return ranked(filtered + behind + unresolved)
    }

    private static func projectedLowVolumeInsight(for part: BodyPart,
                                                  completedSets: Double,
                                                  plannedSets: Double,
                                                  projectedSets: Double,
                                                  experience: ExperienceLevel) -> Insight {
        let bands = VolumeLandmarks.bands(for: part, experience: experience)
        let name = part.displayName
        return Insight(
            id: "volume.\(part.rawValue)",
            kind: .volume,
            part: part,
            title: "\(name) volume is projected low",
            message: "\(name): \(Format.sets(completedSets)) completed so far + \(Format.sets(plannedSets)) planned this week — still below target.",
            detail: "\(name) is projected for \(Format.sets(projectedSets)) sets this week after planned remaining work. Coach's starting range for your experience is ~\(Format.sets(bands.mev))–\(Format.sets(bands.mav)) sets/week, so the plan likely needs more \(name.lowercased()) work.",
            citation: CitationRegistry.volumeDoseResponse,
            severity: .attention)
    }

    private static func behindPlanInsights(facts: TrainingFacts,
                                           accounting: PlanAwareWeeklyAccounting,
                                           isBehindPlan: Bool,
                                           plan: WeeklyPlan,
                                           now: Date) -> [Insight] {
        guard isBehindPlan, lateEnoughForBehindPlan(plan: plan, now: now) else { return [] }
        var result: [Insight] = []
        for part in BodyPart.allCases {
            let completed = accounting.completedSetsByPart[part] ?? 0
            let planned = accounting.plannedRemainingSetsByPart[part] ?? 0
            let projected = accounting.projectedSetsByPart[part] ?? completed
            guard planned > 0 else { continue }
            guard VolumeLandmarks.zone(sets: completed, for: part, experience: facts.experience) == .belowMEV else { continue }
            guard VolumeLandmarks.zone(sets: projected, for: part, experience: facts.experience) != .belowMEV else { continue }

            let name = part.displayName
            result.append(Insight(
                id: "behindPlan.\(part.rawValue)",
                kind: .volume,
                part: part,
                title: "\(name) is behind plan",
                message: "\(name): \(Format.sets(completed)) completed so far, \(Format.sets(planned)) planned this week.",
                detail: "The plan still projects enough \(name.lowercased()) work by week-end, but adherence is behind late in the week. Treat the remaining planned \(name.lowercased()) work as the priority before adding extra volume elsewhere.",
                citation: CitationRegistry.volumeDoseResponse,
                severity: .attention))
        }
        return result
    }

    private static func unresolvedPlanningInsights(deficits: [BodyPart: Double],
                                                   diagnostics: [PlanningDiagnostic],
                                                   experience: ExperienceLevel) -> [Insight] {
        guard !deficits.isEmpty else { return [] }
        let ordered = deficits.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            let ai = BodyPart.allCases.firstIndex(of: a.key) ?? Int.max
            let bi = BodyPart.allCases.firstIndex(of: b.key) ?? Int.max
            return ai < bi
        }
        let summary = ordered
            .map { "\($0.key.displayName) \(Format.sets($0.value))" }
            .joined(separator: ", ")
        let reason: String
        if diagnostics.contains(where: { $0.kind == .recoveryBlocked }) {
            reason = "Some remaining hard work is blocked by recovery eligibility."
        } else if diagnostics.contains(where: { $0.kind == .noStrengthSlots }) {
            reason = "There are no eligible remaining strength slots in the current week."
        } else {
            reason = "The remaining scheduled strength work cannot close every target without exceeding conservative session volume."
        }

        let ranges = ordered.map { part, _ -> String in
            let bands = VolumeLandmarks.bands(for: part, experience: experience)
            return "\(part.displayName) starts around \(Format.sets(bands.mev)) sets/week"
        }.joined(separator: "; ")

        return [Insight(
            id: "planning.unresolvedVolume",
            kind: .volume,
            title: "Some planned volume still needs attention",
            message: "Still projected low after safe planning: \(summary) sets.",
            detail: "\(reason) \(ranges). Keep the planned work as the priority, then adjust the schedule or add another eligible strength slot if recovery allows.",
            citation: CitationRegistry.volumeDoseResponse,
            severity: .attention)]
    }

    private static func lateEnoughForBehindPlan(plan: WeeklyPlan, now: Date) -> Bool {
        let cal = Calendar.current
        let weekStart = WeeklyStats.weekStart(now: plan.generatedAt)
        let today = cal.startOfDay(for: now)
        let elapsed = cal.dateComponents([.day], from: weekStart, to: today).day ?? 0
        return elapsed >= 3
    }

    private static func ranked(_ insights: [Insight]) -> [Insight] {
        var seen = Set<String>()
        return insights
            .filter { seen.insert($0.id).inserted }
            .sorted { a, b in
                if a.severity != b.severity { return a.severity > b.severity }
                return a.id < b.id
            }
    }
}
