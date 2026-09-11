import Foundation

/// Pure Phase 3 authoring operations for the unified plan graph.
///
/// These operations materialize app-owned plans. DB++ remains the resistance
/// planning/evaluation authority after materialization; cardio, mobility,
/// instruction, scheduling, templates, and repeat semantics stay app-owned.
public enum UnifiedPlanAuthoring {
    public static func instantiate(template: PlanTemplate,
                                   from request: PlanningRequest,
                                   now: Date = Date()) throws -> Plan {
        try request.validate()
        try template.validate()

        // A profile may be entered more than once as estimates are refreshed.
        // The request order is meaningful: the last profile is the newest one.
        let profiles = Dictionary(
            request.performanceProfiles.map { ($0.exerciseKey, $0) },
            uniquingKeysWith: { _, newest in newest })
        let weeks = template.weeks.enumerated().map { index, week in
            materialize(week: week, index: index, profiles: profiles)
        }
        let horizon: PlanHorizon
        let cycleLengthDays: Int
        switch request.horizon {
        case let .nativeCycle(days):
            horizon = .nativeCycle(days: days)
            cycleLengthDays = days
        case .singleWeek where weeks.count == 1:
            horizon = .singleWeek
            cycleLengthDays = 7
        default:
            horizon = .mesocycle(weeks: weeks.count)
            cycleLengthDays = 7
        }

        var plan = Plan(
            title: template.title,
            provenance: .templateAuthored(templateID: template.id, adaptedBy: .selfAthlete),
            goal: template.goal,
            horizon: horizon,
            weeks: weeks,
            createdAt: now,
            updatedAt: now,
            cycleLengthDays: cycleLengthDays,
            authoredOnIdiom: nil,
            status: .draft,
            notes: template.evidenceNotes,
            rationale: template.rationale,
            assistance: nil,
            setSchemes: template.setSchemes)

        if let model = request.periodization, model != .none, weeks.count == 1 {
            let requestedWeeks: Int = {
                if case let .mesocycle(value) = request.horizon { return value }
                return 1
            }()
            plan = try mesocycle(
                from: plan,
                weeks: requestedWeeks,
                periodization: model,
                progression: request.progression,
                now: now)
        } else {
            try plan.validate()
        }
        return plan
    }

    /// Adds copies of one session to selected days in one week. Copies receive
    /// fresh identities and reset execution state, so a repeat can never alias
    /// actual results from the source session.
    public static func repeatSession(id sessionID: UUID,
                                     on weekdays: Set<Weekday>,
                                     weekIndex: Int = 0,
                                     in plan: inout Plan,
                                     now: Date = Date()) throws {
        guard !weekdays.isEmpty else { throw UnifiedPlanValidationError.invalidRepeatRequest }
        guard plan.weeks.indices.contains(weekIndex) else {
            throw UnifiedPlanValidationError.sourceWeekNotFound(weekIndex)
        }
        guard let source = plan.weeks[weekIndex].days
            .flatMap(\.sessions)
            .first(where: { $0.id == sessionID }) else {
            throw UnifiedPlanValidationError.sourceSessionNotFound
        }

        var updated = plan
        var week = updated.weeks[weekIndex]
        for weekday in ManualPlanBuilder.mondayFirst where weekdays.contains(weekday) {
            guard let dayIndex = week.days.firstIndex(where: { $0.weekday == weekday }) else {
                throw UnifiedPlanValidationError.weekdaysMustBeMondayFirst
            }
            guard week.days[dayIndex].sessions.count < 2 else {
                throw UnifiedPlanValidationError.dayHasTooManySessions(weekday)
            }
            week.days[dayIndex].sessions.append(copySession(source))
        }
        updated.weeks[weekIndex] = week
        updated.updatedAt = now
        try updated.validate()
        plan = updated
    }

    /// Carries a week forward into a mesocycle. Progression is applied only to
    /// newly materialized weeks and never mutates the source week in place.
    public static func mesocycle(from plan: Plan,
                                 weeks count: Int,
                                 periodization: PeriodizationModel = .none,
                                 progression: ProgressionIntent? = nil,
                                 now: Date = Date()) throws -> Plan {
        guard (1...52).contains(count) else {
            throw UnifiedPlanValidationError.invalidMesocycleLength
        }
        guard let source = plan.weeks.first else {
            throw UnifiedPlanValidationError.planHasNoWeeks
        }

        let selectedProgression = progression ?? source.intendedProgression
        let generatedWeeks = (0..<count).map { index in
            var week = copyWeek(source, index: index)
            week.intendedProgression = selectedProgression
            let isDeload = periodization == .accumulationIntensificationDeload
                && count >= 4 && index == count - 1
            week.isDeload = isDeload
            week = transform(week, progression: selectedProgression,
                             weekOffset: index, isDeload: isDeload)
            return week
        }

        var result = plan
        result.horizon = .mesocycle(weeks: count)
        result.cycleLengthDays = 7
        result.weeks = generatedWeeks
        result.phases = phases(for: periodization, weeks: count,
                               progression: selectedProgression,
                               cycleLengthDays: result.cycleLengthDays)
        result.updatedAt = now
        try result.validate()
        return result
    }

    /// Repeats the selected source week one or more times, applying the same
    /// deterministic progression used by mesocycle generation.
    public static func repeatWeek(at sourceIndex: Int = 0,
                                  count: Int = 1,
                                  in plan: inout Plan,
                                  progression: ProgressionIntent? = nil,
                                  now: Date = Date()) throws {
        guard count > 0 else { throw UnifiedPlanValidationError.invalidRepeatRequest }
        guard plan.weeks.indices.contains(sourceIndex) else {
            throw UnifiedPlanValidationError.sourceWeekNotFound(sourceIndex)
        }
        let source = plan.weeks[sourceIndex]
        var updated = plan
        let selectedProgression = progression ?? source.intendedProgression
        for _ in 0..<count {
            let index = updated.weeks.count
            let copy = transform(
                copyWeek(source, index: index),
                progression: selectedProgression,
                weekOffset: index,
                isDeload: false)
            updated.weeks.append(copy)
        }
        updated.horizon = .mesocycle(weeks: updated.weeks.count)
        updated.cycleLengthDays = 7
        updated.updatedAt = now
        try updated.validate()
        plan = updated
    }

    private static func materialize(week: PlanWeek, index: Int,
                                    profiles: [ExerciseKey: ExercisePerformanceProfile]) -> PlanWeek {
        var copy = copyWeek(week, index: index)
        for dayIndex in copy.days.indices {
            for sessionIndex in copy.days[dayIndex].sessions.indices {
                var session = copy.days[dayIndex].sessions[sessionIndex]
                session.items = session.items.map { item in
                    guard case let .strength(strength) = item else { return copyItem(item) }
                    let estimate = profiles[strength.exerciseKey]?.latestEstimate?.valueKg
                    var adapted = copyStrength(strength)
                    adapted.sets = adapted.sets.map { set in
                        guard case let .percent1RM(percent, _) = set.load,
                              let estimate else { return set }
                        var resolved = set
                        resolved.load = .percent1RM(
                            percent: percent,
                            calculatedWeight: estimate * percent)
                        return resolved
                    }
                    return .strength(adapted)
                }
                copy.days[dayIndex].sessions[sessionIndex] = session
            }
        }
        return copy
    }

    private static func transform(_ week: PlanWeek,
                                  progression: ProgressionIntent?,
                                  weekOffset: Int,
                                  isDeload: Bool) -> PlanWeek {
        var copy = week
        for dayIndex in copy.days.indices {
            for sessionIndex in copy.days[dayIndex].sessions.indices {
                var session = copy.days[dayIndex].sessions[sessionIndex]
                session.items = session.items.map { item in
                    guard case let .strength(strength) = item else { return item }
                    var adapted = strength
                    adapted.sets = adapted.sets.map { set in
                        transformedSet(set, progression: progression,
                                       weekOffset: weekOffset, isDeload: isDeload)
                    }
                    if isDeload {
                        let warmups = adapted.sets.filter { $0.kind == .warmup }
                        let working = adapted.sets.filter { $0.kind != .warmup }
                        let keepCount = max(1, Int(Double(working.count) * 0.6))
                        adapted.sets = renumber(warmups + Array(working.prefix(keepCount)))
                    }
                    if progression == .volume, !isDeload, weekOffset > 0,
                       let last = adapted.sets.last {
                        var extra = last
                        extra = PrescribedSet(
                            setIndex: adapted.sets.count,
                            kind: .working,
                            repTarget: extra.repTarget,
                            load: extra.load,
                            targetRPE: extra.targetRPE,
                            targetRIR: extra.targetRIR,
                            restSeconds: extra.restSeconds,
                            trainerNote: extra.trainerNote,
                            targetRPERange: extra.targetRPERange,
                            targetRIRRange: extra.targetRIRRange)
                        adapted.sets.append(extra)
                    }
                    return .strength(adapted)
                }
                copy.days[dayIndex].sessions[sessionIndex] = session
            }
        }
        return copy
    }

    private static func transformedSet(_ set: PrescribedSet,
                                       progression: ProgressionIntent?,
                                       weekOffset: Int,
                                       isDeload: Bool) -> PrescribedSet {
        var result = set
        if isDeload {
            if let rpe = result.targetRPE { result.targetRPE = max(0, rpe - 1) }
            if let rir = result.targetRIR { result.targetRIR = min(10, rir + 1) }
            result.load = scale(result.load, by: 0.9)
            return result
        }
        guard weekOffset > 0 else { return result }
        switch progression {
        case .linearLoad:
            result.load = scale(result.load, by: pow(1.025, Double(weekOffset)))
        case .doubleProgression:
            switch result.repTarget {
            case let .exact(reps): result.repTarget = .exact(reps + weekOffset)
            case let .range(min, max):
                result.repTarget = .range(min: min + weekOffset, max: max + weekOffset)
            default: break
            }
        case .percentageBased, .autoregulated, .volume, .none:
            break
        }
        return result
    }

    private static func scale(_ load: LoadPrescription, by factor: Double) -> LoadPrescription {
        switch load {
        case let .absoluteWeight(value, unit):
            return .absoluteWeight(value: value * factor, unit: unit)
        case let .percent1RM(percent, calculatedWeight):
            return .percent1RM(percent: percent,
                               calculatedWeight: calculatedWeight.map { $0 * factor })
        case let .bodyweightPlus(value, unit):
            return .bodyweightPlus(value: value * factor, unit: unit)
        case let .assisted(value, unit):
            return .assisted(value: value * factor, unit: unit)
        default:
            return load
        }
    }

    private static func renumber(_ sets: [PrescribedSet]) -> [PrescribedSet] {
        sets.enumerated().map { index, set in
            PrescribedSet(
                setIndex: index,
                kind: set.kind,
                repTarget: set.repTarget,
                load: set.load,
                targetRPE: set.targetRPE,
                targetRIR: set.targetRIR,
                restSeconds: set.restSeconds,
                trainerNote: set.trainerNote,
                targetRPERange: set.targetRPERange,
                targetRIRRange: set.targetRIRRange)
        }
    }

    private static func phases(for model: PeriodizationModel, weeks: Int,
                               progression: ProgressionIntent?,
                               cycleLengthDays: Int) -> [PlanPhase]? {
        guard model != .none else { return nil }
        switch model {
        case .accumulationIntensificationDeload:
            var result = [PlanPhase(
                id: "accumulation", title: "Accumulation",
                durationCycles: max(1, weeks - 2),
                cycleLengthDays: cycleLengthDays,
                progression: progression)]
            if weeks > 2 {
                result.append(PlanPhase(
                    id: "intensification", title: "Intensification",
                    durationCycles: 1,
                    cycleLengthDays: cycleLengthDays,
                    progression: progression))
            }
            if weeks >= 4 {
                result.append(PlanPhase(
                    id: "deload", title: "Deload", durationCycles: 1,
                    cycleLengthDays: cycleLengthDays,
                    progression: progression, isDeload: true))
            }
            return result
        case .linear: return [phase("linear", "Linear", weeks, progression, cycleLengthDays)]
        case .dailyUndulating: return [phase("daily-undulating", "Daily undulating", weeks, progression, cycleLengthDays)]
        case .block: return [phase("block", "Block", weeks, progression, cycleLengthDays)]
        case .none: return nil
        }
    }

    private static func phase(_ id: String, _ title: String, _ weeks: Int,
                              _ progression: ProgressionIntent?, _ cycleLengthDays: Int) -> PlanPhase {
        PlanPhase(id: id, title: title, durationCycles: weeks,
                  cycleLengthDays: cycleLengthDays, progression: progression)
    }

    private static func copyWeek(_ source: PlanWeek, index: Int) -> PlanWeek {
        PlanWeek(index: index, days: source.days.map { day in
            PlanDay(weekday: day.weekday, sessions: day.sessions.map(copySession))
        }, intendedProgression: source.intendedProgression, isDeload: source.isDeload)
    }

    private static func copySession(_ source: Session) -> Session {
        Session(title: source.title, goal: source.goal,
                items: source.items.map(copyItem),
                estimatedDurationMinutes: source.estimatedDurationMinutes,
                status: .planned, startedAt: nil, completedAt: nil,
                sessionRPE: nil, painFlag: nil, note: source.note,
                partners: source.partners.map { PartnerRef(displayName: $0.displayName, linkedUserID: $0.linkedUserID) })
    }

    private static func copyItem(_ item: WorkoutItem) -> WorkoutItem {
        switch item {
        case let .strength(value): return .strength(copyStrength(value))
        case let .cardio(value):
            return .cardio(CardioItem(order: value.order, prescription: value.prescription,
                                      instructions: value.instructions))
        case let .mobility(value):
            return .mobility(MobilityItem(order: value.order, name: value.name,
                                          rounds: value.rounds, perRound: value.perRound,
                                          eachSide: value.eachSide, instructions: value.instructions))
        case let .instruction(value):
            return .instruction(InstructionItem(order: value.order, text: value.text))
        }
    }

    private static func copyStrength(_ source: StrengthItem) -> StrengthItem {
        StrengthItem(exerciseKey: source.exerciseKey, order: source.order,
                     instructions: source.instructions, tempo: source.tempo,
                     defaultRestSeconds: source.defaultRestSeconds,
                     alternateExerciseKey: source.alternateExerciseKey,
                     sets: source.sets.map { set in
                         PrescribedSet(setIndex: set.setIndex, kind: set.kind,
                                       repTarget: set.repTarget, load: set.load,
                                       targetRPE: set.targetRPE, targetRIR: set.targetRIR,
                                       restSeconds: set.restSeconds,
                                       trainerNote: set.trainerNote,
                                       targetRPERange: set.targetRPERange,
                                       targetRIRRange: set.targetRIRRange)
                     }, schemeApplied: source.schemeApplied,
                     supersetGroup: source.supersetGroup,
                     laterality: source.laterality,
                     progression: source.progression,
                     performerOverrides: source.performerOverrides)
    }
}
