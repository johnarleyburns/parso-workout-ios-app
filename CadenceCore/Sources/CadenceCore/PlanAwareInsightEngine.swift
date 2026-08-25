import Foundation

public struct PlanAwareWeeklyAccounting: Sendable, Equatable {
    public let completedSetsByGroup: [MuscleGroup: Double]
    public let plannedRemainingSetsByGroup: [MuscleGroup: Double]
    public let projectedSetsByGroup: [MuscleGroup: Double]
    public let plannedStrengthSessionCount: Int

    public init(completed: TrainingFacts, plannedStrengthSessions: [CoachSession]) {
        self.completedSetsByGroup = completed.weeklySetsByGroup
        self.plannedRemainingSetsByGroup = Self.plannedSetsByGroup(from: plannedStrengthSessions)
        self.projectedSetsByGroup = completedSetsByGroup
            .merging(plannedRemainingSetsByGroup) { $0 + $1 }
        self.plannedStrengthSessionCount = plannedStrengthSessions.filter { $0.kind == .strength }.count
    }

    public static func plannedSetsByGroup(from sessions: [CoachSession]) -> [MuscleGroup: Double] {
        plannedSetsByGroup(from: sessions.flatMap { session -> [CoachSession.RecommendedExercise] in
            guard session.kind == .strength else { return [] }
            return session.exercises ?? []
        })
    }

    public static func plannedSetsByGroup(from exercises: [CoachSession.RecommendedExercise]) -> [MuscleGroup: Double] {
        var result: [MuscleGroup: Double] = [:]
        for exercise in exercises {
            let sets = Double(max(1, exercise.sets ?? 3))
            for (group, weight) in credits(for: exercise) {
                result[group, default: 0] += sets * weight
            }
        }
        return result
    }

    /// The credit one planned set of this recommendation gives each muscle group.
    ///
    /// A recommendation carries only a name and (sometimes) a primary muscle list,
    /// so resolve it to a catalog template first — that is where the DB++ roles and
    /// volume eligibility live. Falls back to the recommendation's own muscles, then
    /// to a category guess from the name.
    static func credits(for exercise: CoachSession.RecommendedExercise) -> [MuscleGroup: Double] {
        if let template = ExerciseLibrary.byName[exercise.name.lowercased()] {
            return VolumeCredit.credits(for: template)
        }
        if !exercise.primaryMuscles.isEmpty {
            return VolumeCredit.credits(direct: MuscleGroup.canonicalize(exercise.primaryMuscles),
                                        indirect: [], volumeEligible: true)
        }
        if let category = ExerciseCategory.guess(fromName: exercise.name) {
            return VolumeCredit.credits(direct: MuscleGroup.defaults(forCategory: category),
                                        indirect: [], volumeEligible: true)
        }
        return [:]
    }
}

public enum PlanAwareInsightEngine {
    public static func run(completed facts: TrainingFacts,
                           plan: WeeklyPlan,
                           plannedStrengthSessions: [CoachSession],
                           unresolvedDeficits: [MuscleGroup: Double] = [:],
                           diagnostics: [PlanningDiagnostic] = [],
                           isBehindPlan: Bool = false,
                           now: Date = Date(),
                           isOverrideActive: Bool = false) -> [Insight] {
        let base = InsightEngine.run(facts)
        guard base.first?.kind != .coldStart else { return base }

        let accounting = PlanAwareWeeklyAccounting(completed: facts,
                                                   plannedStrengthSessions: plannedStrengthSessions)
        guard accounting.plannedStrengthSessionCount > 0 else {
            guard !unresolvedDeficits.isEmpty else { return base }
            let unresolvedGroups = Set(unresolvedDeficits.keys)
            let filtered = base.filter { insight in
                guard insight.kind == .volume,
                      insight.severity == .attention,
                      insight.title.localizedCaseInsensitiveContains("low"),
                      let group = insight.group else { return true }
                // Suppress for unresolved groups AND for groups with 0 completed
                // sets — the user can't address new muscle groups mid-week.
                if unresolvedGroups.contains(group) { return false }
                return (facts.weeklySetsByGroup[group] ?? 0) > 0
            }
            return ranked(filtered + unresolvedPlanningInsights(deficits: unresolvedDeficits,
                                                                diagnostics: diagnostics,
                                                                experience: facts.experience,
                                                                isOverrideActive: isOverrideActive))
        }

        let unresolvedGroups = Set(unresolvedDeficits.keys)
        let earlyWeek = isEarlyWeek(plan: plan, now: now)
        let filtered = base.compactMap { insight -> Insight? in
            guard insight.kind == .volume,
                  insight.severity == .attention,
                  let group = insight.group,
                  insight.title.localizedCaseInsensitiveContains("low") else {
                return insight
            }

            if unresolvedGroups.contains(group) {
                return nil
            }

            let completedSets = accounting.completedSetsByGroup[group] ?? 0
            let plannedSets = accounting.plannedRemainingSetsByGroup[group] ?? 0

            // When other deficits exist and this group has 0 completed sets, the
            // user cannot realistically add a new muscle group mid-week — suppress
            // the individual nag and rely on the unresolvedPlanningInsights aggregate.
            if !unresolvedDeficits.isEmpty && completedSets == 0 {
                return nil
            }

            // Fix the raw-insight leak: a group with no completed work AND no
            // planned remaining work should not produce a per-group "low" nag.
            // If the plan genuinely cannot cover it, the unresolvedPlanningInsights
            // aggregate on line 176 already reports it honestly as a coach-side
            // planning note. If the plan covers it (projected >= MEV), the
            // guard below already drops it.
            if completedSets == 0 && plannedSets == 0 {
                return nil
            }

            // Early-week proration: before day ~3, a group that has 0 completed
            // sets and no planned remaining work gets at most the projected
            // framing (which won't trigger here since plannedSets is 0). More
            // importantly, a group with planned remaining work gets the projected
            // framing instead of the bare "0/6 this week." This prevents the
            // Tuesday-morning "everything reads low" artifact from the
            // non-prorated Monday→now weekly window.
            if earlyWeek && completedSets == 0 && plannedSets > 0 {
                let projectedSets = completedSets + plannedSets
                let projectedZone = VolumeLandmarks.zone(sets: projectedSets, for: group,
                                                          experience: facts.experience)
                guard projectedZone == .belowMEV else { return nil }
                return projectedLowVolumeInsight(for: group,
                                                  completedSets: completedSets,
                                                  plannedSets: plannedSets,
                                                  projectedSets: projectedSets,
                                                  experience: facts.experience)
            }

            let projectedSets = accounting.projectedSetsByGroup[group] ?? 0
            let projectedZone = VolumeLandmarks.zone(sets: projectedSets,
                                                      for: group,
                                                      experience: facts.experience)
            guard projectedZone == .belowMEV else { return nil }

            guard plannedSets > 0 else { return insight }
            return projectedLowVolumeInsight(for: group,
                                              completedSets: accounting.completedSetsByGroup[group] ?? 0,
                                              plannedSets: plannedSets,
                                              projectedSets: projectedSets,
                                              experience: facts.experience)
        }

        let behind = behindPlanInsights(facts: facts, accounting: accounting,
                                        isBehindPlan: isBehindPlan, plan: plan, now: now)

        let resolved: Set<MuscleGroup>
        let resolvedSets: [MuscleGroup: Double]
        if unresolvedDeficits.isEmpty {
            resolved = Set(accounting.plannedRemainingSetsByGroup.keys)
            resolvedSets = accounting.plannedRemainingSetsByGroup
        } else {
            let plannedKeys = Set(accounting.plannedRemainingSetsByGroup.keys)
            let unresolvedKeys = Set(unresolvedDeficits.keys)
            resolved = plannedKeys.subtracting(unresolvedKeys)
                .intersection(Set(MuscleGroup.allCases))
            resolvedSets = resolved.reduce(into: [:]) { $0[$1] = accounting.plannedRemainingSetsByGroup[$1] ?? 0 }
        }

        let unresolved = unresolvedPlanningInsights(deficits: unresolvedDeficits,
                                                     diagnostics: diagnostics,
                                                     experience: facts.experience,
                                                     resolvedGroups: resolved,
                                                     resolvedSets: resolvedSets,
                                                     isOverrideActive: isOverrideActive)

        var result = filtered + behind + unresolved
        if isOverrideActive {
            result.append(overrideActiveInsight)
        }
        return ranked(result)
    }

    private static func projectedLowVolumeInsight(for group: MuscleGroup,
                                                  completedSets: Double,
                                                  plannedSets: Double,
                                                  projectedSets: Double,
                                                  experience: ExperienceLevel) -> Insight {
        let bands = VolumeLandmarks.bands(for: group, experience: experience)
        let name = group.displayName
        return Insight(
            id: "volume.\(group.rawValue)",
            kind: .volume,
            group: group,
            title: "\(name) volume is projected low",
            message: "\(name): \(Format.sets(completedSets)) done + \(Format.sets(plannedSets)) planned = \(Format.progress(done: projectedSets, target: bands.mev, unit: "sets")) this week.",
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
        for group in MuscleGroup.canonicalOrder {
            let completed = accounting.completedSetsByGroup[group] ?? 0
            let planned = accounting.plannedRemainingSetsByGroup[group] ?? 0
            let projected = accounting.projectedSetsByGroup[group] ?? completed
            guard planned > 0 else { continue }
            guard VolumeLandmarks.zone(sets: completed, for: group, experience: facts.experience) == .belowMEV else { continue }
            guard VolumeLandmarks.zone(sets: projected, for: group, experience: facts.experience) != .belowMEV else { continue }

            let name = group.displayName
            result.append(Insight(
                id: "behindPlan.\(group.rawValue)",
                kind: .volume,
                group: group,
                title: "\(name) is behind plan",
                message: "\(name): \(Format.sets(completed)) done this week, \(Format.sets(planned)) planned remaining — do the planned sets to stay on target.",
                detail: "The plan still projects enough \(name.lowercased()) work by week-end, but adherence is behind late in the week. Treat the remaining planned \(name.lowercased()) work as the priority before adding extra volume elsewhere.",
                citation: CitationRegistry.volumeDoseResponse,
                severity: .attention))
        }
        return result
    }

    private static func unresolvedPlanningInsights(deficits: [MuscleGroup: Double],
                                                    diagnostics: [PlanningDiagnostic],
                                                    experience: ExperienceLevel,
                                                    resolvedGroups: Set<MuscleGroup> = [],
                                                    resolvedSets: [MuscleGroup: Double] = [:],
                                                    isOverrideActive: Bool = false) -> [Insight] {
        if deficits.isEmpty && resolvedGroups.isEmpty { return [] }

        // Fully resolved — no suggestion. A successful plan adjustment is not
        // actionable feedback and should not become "volume gaps closed" noise.
        if deficits.isEmpty && !resolvedGroups.isEmpty {
            return []
        }

        // Partially resolved — note what was added AND what's still short
        if !deficits.isEmpty && !resolvedGroups.isEmpty {
            let added = resolvedGroups.sorted { groupIdx($0) < groupIdx($1) }
                .map { "\($0.displayName) +\(Format.sets(resolvedSets[$0] ?? 0))" }
                .joined(separator: ", ")
            let ordered = deficits.sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return groupIdx(a.key) < groupIdx(b.key)
            }
            let short = ordered
                .map { "\($0.key.displayName) \(Format.sets($0.value))" }
                .joined(separator: ", ")
            let reason = diagnosticReason(diagnostics)
            let ranges = ordered.map { group, _ -> String in
                let bands = VolumeLandmarks.bands(for: group, experience: experience)
                return "\(group.displayName) starts around \(Format.sets(bands.mev)) sets/week"
            }.joined(separator: "; ")

            return [Insight(
                id: "planning.partialResolved",
                kind: .volume,
                title: "Some volume still needs attention",
                message: "Added to tonight: \(added). Still short: \(short) sets to go.",
                detail: "\(reason) \(ranges). Coach added what fits safely; the remaining gap needs another eligible slot or a schedule adjustment.",
                citation: CitationRegistry.volumeDoseResponse,
                severity: .attention,
                action: isOverrideActive ? .revertToSafePlan :
                    .addGapsToPlan(deficits: deficits))]
        }

        // None resolved — keep existing nag
        let ordered = deficits.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            return groupIdx(a.key) < groupIdx(b.key)
        }
        let summary = ordered
            .map { "\($0.key.displayName) \(Format.sets($0.value))" }
            .joined(separator: ", ")
        let reason = diagnosticReason(diagnostics)
        let ranges = ordered.map { group, _ -> String in
            let bands = VolumeLandmarks.bands(for: group, experience: experience)
            return "\(group.displayName) starts around \(Format.sets(bands.mev)) sets/week"
        }.joined(separator: "; ")

        return [Insight(
            id: "planning.unresolvedVolume",
            kind: .volume,
            title: "Some planned volume still needs attention",
            message: "Still short after safe planning: \(summary) sets to go.",
            detail: "\(reason) \(ranges). Keep the planned work as the priority, then adjust the schedule or add another eligible strength slot if recovery allows.",
            citation: CitationRegistry.volumeDoseResponse,
            severity: .attention,
            action: isOverrideActive ? .revertToSafePlan :
                .addGapsToPlan(deficits: deficits))]
    }

    private static func groupIdx(_ group: MuscleGroup) -> Int {
        MuscleGroup.canonicalIndex(group)
    }

    private static func diagnosticReason(_ diagnostics: [PlanningDiagnostic]) -> String {
        if diagnostics.contains(where: { $0.kind == .recoveryBlocked }) {
            return "Some remaining hard work is blocked by recovery eligibility."
        } else if diagnostics.contains(where: { $0.kind == .noStrengthSlots }) {
            return "There are no eligible remaining strength slots in the current week."
        } else {
            return "The remaining scheduled strength work cannot close every target without exceeding conservative session volume."
        }
    }

    private static func lateEnoughForBehindPlan(plan: WeeklyPlan, now: Date) -> Bool {
        let cal = Calendar.current
        let weekStart = WeeklyStats.weekStart(now: plan.generatedAt)
        let today = cal.startOfDay(for: now)
        let elapsed = cal.dateComponents([.day], from: weekStart, to: today).day ?? 0
        return elapsed >= 3
    }

    private static func isEarlyWeek(plan: WeeklyPlan, now: Date) -> Bool {
        let cal = Calendar.current
        let weekStart = WeeklyStats.weekStart(now: plan.generatedAt)
        let today = cal.startOfDay(for: now)
        let elapsed = cal.dateComponents([.day], from: weekStart, to: today).day ?? 0
        return elapsed < 3
    }

    private static var overrideActiveInsight: Insight {
        Insight(
            id: "planning.overrideActive",
            kind: .volume,
            title: "Planning past safe guardrails this week",
            message: "At your request, Coach is planning past recovery eligibility and session-size limits until Sunday. Watch for performance drops.",
            detail: "The productive-volume targets are evidence-informed starting points, not fixed laws. Individual response varies, and you always have the final say. But persistent overload without recovery impairs adaptation.",
            citation: CitationRegistry.volumeDoseResponse,
            severity: .info,
            action: .revertToSafePlan)
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
