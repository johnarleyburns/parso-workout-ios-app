import Foundation

/// The DB++ view of a unified plan. DB++'s canonical PLAN is resistance-only;
/// app-only item identities are intentionally reported instead of discarded.
public struct UnifiedPlanDBPPProjection: Sendable, Equatable {
    public let plan: DBPPWorkoutPlan
    public let projectedItemIDs: [UUID]
    public let omittedItemIDs: [UUID]

    public init(plan: DBPPWorkoutPlan,
                projectedItemIDs: [UUID], omittedItemIDs: [UUID]) {
        self.plan = plan
        self.projectedItemIDs = projectedItemIDs
        self.omittedItemIDs = omittedItemIDs
    }
}

/// A small app-facing summary of DB++ PLAN evaluation. The complete canonical
/// evaluation remains available to the bridge but is not persisted in the
/// unified Plan, keeping the app model stable as DB++ adds diagnostic fields.
public struct UnifiedPlanEngineEvaluation: Codable, Sendable, Equatable {
    public let status: String
    public let hardConstraintViolations: Int
    public let targetGaps: Int
    public let softPreferenceWarnings: Int
    public let satisfiesHardConstraints: Bool
    public let meetsTargetMinimums: Bool
    public let warnings: [String]
    public let projectedItemCount: Int
    public let omittedAppItemCount: Int

    public init(status: String, hardConstraintViolations: Int,
                targetGaps: Int, softPreferenceWarnings: Int,
                satisfiesHardConstraints: Bool, meetsTargetMinimums: Bool,
                warnings: [String], projectedItemCount: Int,
                omittedAppItemCount: Int) {
        self.status = status
        self.hardConstraintViolations = hardConstraintViolations
        self.targetGaps = targetGaps
        self.softPreferenceWarnings = softPreferenceWarnings
        self.satisfiesHardConstraints = satisfiesHardConstraints
        self.meetsTargetMinimums = meetsTargetMinimums
        self.warnings = warnings
        self.projectedItemCount = projectedItemCount
        self.omittedAppItemCount = omittedAppItemCount
    }
}

/// Converts the mixed app plan to and from the portion DB++ explicitly owns.
/// This is a projection, not a second persistence model: the app Plan remains
/// the source of truth for execution and for non-resistance item families.
public enum UnifiedPlanDBPPBridge {
    public static let engineVersion = "1.16.0"
    public static let planSchemaVersion = "0.2.0"

    public static func project(_ plan: Plan) -> UnifiedPlanDBPPProjection {
        var projectedIDs: [UUID] = []
        var omittedIDs: [UUID] = []
        var sessions: [DBPPPlanSession] = []

        for (weekIndex, week) in plan.weeks.enumerated() {
            for (dayIndex, day) in week.days.enumerated() {
                let strengthSessions = day.sessions.compactMap { session -> DBPPPlanSession? in
                    let strengths = session.items.compactMap { item -> DBPPPlanExercisePrescription? in
                        guard case let .strength(strength) = item else {
                            omittedIDs.append(item.id)
                            return nil
                        }
                        projectedIDs.append(strength.id)
                        return prescription(from: strength)
                    }
                    guard !strengths.isEmpty else { return nil }
                    let phaseID = phaseID(for: weekIndex, in: plan)
                    return DBPPPlanSession(
                        planSessionId: session.id.uuidString,
                        phaseId: phaseID,
                        dayOffset: weekIndex * plan.cycleLengthDays + dayIndex,
                        name: session.title,
                        notes: session.note,
                        exercises: strengths)
                }
                sessions.append(contentsOf: strengthSessions)
            }
        }

        let phases = plan.phases?.map { phase in
            DBPPPlanPhase(
                phaseId: phase.id,
                durationCycles: phase.durationCycles,
                cycle: phase.cycleLengthDays.map(DBPPPlanCycle.init(lengthDays:)))
        }
        let dbPlan = DBPPWorkoutPlan(
            schemaVersion: planSchemaVersion,
            planId: plan.id.raw.uuidString,
            revisionId: plan.revisionID,
            name: plan.title,
            description: plan.notes,
            provenance: .object([
                "engine": DBPPJSONValue.string(plan.engineProvenance?.engine ?? "cadence"),
                "engineVersion": DBPPJSONValue.string(plan.engineProvenance?.engineVersion ?? engineVersion),
                "sourcePlanID": DBPPJSONValue.string(plan.id.raw.uuidString),
                "sourceRevisionID": DBPPJSONValue.string(plan.revisionID)
            ]),
            cycle: .init(lengthDays: max(1, plan.cycleLengthDays)),
            notes: plan.notes,
            phases: phases,
            sessions: sessions)
        return UnifiedPlanDBPPProjection(
            plan: dbPlan,
            projectedItemIDs: projectedIDs,
            omittedItemIDs: omittedIDs)
    }

    public static func evaluate(
        _ plan: Plan,
        experience: ExperienceLevel,
        schedule: CoachSchedulePreferences
    ) -> UnifiedPlanEngineEvaluation? {
        guard TrainingEngineBridge.shared != nil else { return nil }
        let projection = project(plan)
        let profile = TrainingEngineBridge.trainingProfile(
            experience: experience,
            schedule: schedule,
            availableEquipment: Equipment.allCases)
        let target = TrainingEngineBridge.volumeTarget(
            trackedGroups: schedule.trackedMuscleGroups,
            experience: experience,
            periodDays: max(1, plan.cycleLengthDays))
        let result = TrainingEngineBridge.shared?.evaluatePlan(
            projection.plan, profile: profile, target: target)
        guard let result else { return nil }
        return UnifiedPlanEngineEvaluation(
            status: result.status,
            hardConstraintViolations: result.summary.hardConstraintViolations,
            targetGaps: result.summary.targetGaps,
            softPreferenceWarnings: result.summary.softPreferenceWarnings,
            satisfiesHardConstraints: result.summary.satisfiesHardConstraints,
            meetsTargetMinimums: result.summary.meetsTargetMinimums,
            warnings: result.warnings,
            projectedItemCount: projection.projectedItemIDs.count,
            omittedAppItemCount: projection.omittedItemIDs.count)
    }

    public static func provenance(for plan: Plan) -> PlanEngineProvenance {
        PlanEngineProvenance(
            engine: "free-exercise-db-plusplus",
            engineVersion: engineVersion,
            planID: plan.id.raw.uuidString,
            revisionID: plan.revisionID,
            policyID: "cadence-unified-coach-v1",
            schemaVersion: planSchemaVersion)
    }

    private static func phaseID(for weekIndex: Int, in plan: Plan) -> String? {
        guard let phases = plan.phases, !phases.isEmpty else { return nil }
        var cursor = 0
        for phase in phases {
            let cycles = max(1, phase.durationCycles)
            if weekIndex < cursor + cycles { return phase.id }
            cursor += cycles
        }
        return phases.last?.id
    }

    private static func prescription(
        from item: StrengthItem
    ) -> DBPPPlanExercisePrescription {
        let record = TrainingEngineBridge.exerciseRecords.first { record in
            record.exerciseId == item.exerciseKey.raw
                || record.name.caseInsensitiveCompare(item.exerciseKey.raw) == .orderedSame
        }
        let plannedSets = item.sets.sorted { $0.setIndex < $1.setIndex }.map { set in
            DBPPPlannedSet(
                setPrescriptionId: set.id.uuidString,
                setType: dbSetType(for: set.kind),
                reps: repsJSON(for: set.repTarget),
                load: loadJSON(for: set.load),
                effort: effortJSON(for: set),
                notes: set.trainerNote)
        }
        let first = item.sets.sorted { $0.setIndex < $1.setIndex }.first
        let exerciseID = record?.exerciseId
        return DBPPPlanExercisePrescription(
            prescriptionId: item.id.uuidString,
            exerciseId: exerciseID,
            exerciseName: record?.name ?? item.exerciseKey.raw,
            order: item.order + 1,
            sets: DBPPJSONValue.number(Double(plannedSets.count)),
            reps: first.map { repsJSON(for: $0.repTarget) },
            load: first.flatMap { loadJSON(for: $0.load) },
            effort: first.flatMap { effortJSON(for: $0) },
            setType: first.map { dbSetType(for: $0.kind) },
            laterality: item.laterality,
            notes: item.instructions,
            plannedSets: plannedSets.isEmpty ? nil : plannedSets,
            progression: item.progression.map { .string($0.rawValue) })
    }

    private static func dbSetType(for kind: SetKind) -> String {
        switch kind {
        case .warmup: return "warmup"
        case .working: return "working"
        case .backoff: return "backoff"
        case .amrap, .drop: return "other"
        }
    }

    private static func repsJSON(for target: RepTarget) -> DBPPJSONValue {
        switch target {
        case let .exact(reps): return .number(Double(max(0, reps)))
        case let .range(minimum, maximum):
            return .object(["min": .number(Double(max(0, minimum))), "max": .number(Double(max(minimum, maximum)))])
        case let .amrap(minimum):
            return .object(minimum.map { ["min": .number(Double(max(0, $0)))] } ?? [:])
        case let .duration(seconds): return .object(["seconds": .number(Double(max(0, seconds)))])
        case let .distance(meters): return .object(["meters": .number(max(0, meters))])
        }
    }

    private static func loadJSON(for load: LoadPrescription) -> DBPPJSONValue? {
        switch load {
        case let .absoluteWeight(value, unit): return quantity(value: value, unit: unit.rawValue)
        case let .bodyweightPlus(value, unit): return quantity(value: value, unit: unit.rawValue)
        case let .assisted(value, unit): return quantity(value: value, unit: unit.rawValue)
        case let .percent1RM(_, calculatedWeight): return calculatedWeight.map { quantity(value: $0, unit: "kg") }
        case .bodyweight, .band, .machineSetting, .rpeOnly, .unspecified: return nil
        }
    }

    private static func quantity(value: Double, unit: String) -> DBPPJSONValue {
        .object(["value": .number(max(0, value)), "unit": .string(unit)])
    }

    private static func effortJSON(for set: PrescribedSet) -> DBPPJSONValue? {
        var effort: [String: DBPPJSONValue] = [:]
        if let rpe = set.targetRPE { effort["rpe"] = .number(rpe) }
        if let rir = set.targetRIR { effort["rir"] = .number(Double(rir)) }
        if let range = set.targetRPERange {
            effort["rpe"] = .object(["min": .number(range.lowerBound), "max": .number(range.upperBound)])
        }
        if let range = set.targetRIRRange {
            effort["rir"] = .object(["min": .number(Double(range.lowerBound)), "max": .number(Double(range.upperBound))])
        }
        return effort.isEmpty ? nil : .object(effort)
    }
}
