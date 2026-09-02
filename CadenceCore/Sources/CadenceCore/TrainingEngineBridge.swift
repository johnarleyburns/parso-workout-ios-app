import Foundation
import FreeExerciseDBPlusPlus

/// The single boundary between Cadence domain types and the DB++ training engine.
public enum TrainingEngineBridge {
    /// Built once for deterministic, offline use. Callers retain their local defaults
    /// if the bundled database cannot be loaded on a supported device.
    public static let shared: FreeExerciseDBPlusPlus.TrainingEngine? = {
        try? FreeExerciseDBPlusPlus.TrainingEngine.bundled()
    }()

    /// Reads rep and effort defaults from a released DB++ goal policy.
    /// `useSharedEngine` exists so the fallback path can be covered without mutating
    /// process-wide state.
    static func goalDefaults(
        policyId: String,
        useSharedEngine: Bool = true
    ) -> (reps: ClosedRange<Int>, rir: Int)? {
        let engine = useSharedEngine ? shared : nil
        guard let policy = engine?.goalPolicy(policyId),
              case let .object(object) = policy,
              case let .object(reps)? = object["reps"],
              case let .number(lowerBound)? = reps["min"],
              case let .number(upperBound)? = reps["max"],
              case let .object(effort)? = object["effort"],
              case let .number(rir)? = effort["rir"]
        else { return nil }

        return (Int(lowerBound)...Int(upperBound), Int(rir))
    }
}

/// The app-facing read model produced by DB++ `deriveState`. The package's
/// versioned `TrainingState` stays inside the bridge; Home only needs the
/// effective weekly volume rows and a stable provenance marker.
public struct EngineObservationSnapshot: Sendable, Equatable {
    public let subjectId: String
    public let asOf: Date
    public let stateVersion: String
    public let effectiveSetsByMuscle: [String: Double]
    public let unplannedSets: Int
    public let substitutionAdjustedCompletion: Double

    public init(subjectId: String, asOf: Date, stateVersion: String,
                effectiveSetsByMuscle: [String: Double], unplannedSets: Int = 0,
                substitutionAdjustedCompletion: Double = 0) {
        self.subjectId = subjectId
        self.asOf = asOf
        self.stateVersion = stateVersion
        self.effectiveSetsByMuscle = effectiveSetsByMuscle
        self.unplannedSets = unplannedSets
        self.substitutionAdjustedCompletion = substitutionAdjustedCompletion
    }

    public var effectiveSetsByGroup: [MuscleGroup: Double] {
        effectiveSetsByMuscle.reduce(into: [:]) { result, row in
            guard let group = MuscleGroup.canonical(row.key) else { return }
            result[group, default: 0] += row.value
        }
    }
}

// MARK: - Database boundary

extension TrainingEngineBridge {
    /// App-facing snapshot of one DB++ exercise. Keeping this value type here
    /// prevents DB++'s `Exercise` and `JSONValue` types from leaking into the
    /// catalog, evidence, or persistence layers.
    struct ExerciseRecord: Equatable, Sendable {
        let exerciseId: String
        let name: String
        let force: String?
        let level: String?
        let mechanic: String?
        let equipment: String?
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
        let instructions: [String]
        let category: String
        let images: [String]
        let direct: [String]
        let indirect: [String]
        let stabilizers: [String]
        let patterns: [String]
        let volumeEligible: Bool
        let confidence: String?
    }

    struct EvidencePattern: Equatable, Sendable {
        let status: String
        let summary: String
        let references: [String]
    }

    struct EvidenceReference: Equatable, Sendable {
        let title: String
        let type: String
        let url: String
    }

    /// Records are sorted by the stable DB++ exercise id before crossing the
    /// boundary, so catalog seeding remains deterministic across launches.
    static var exerciseRecords: [ExerciseRecord] {
        shared?.database.allExercises.values
            .sorted { $0.exerciseId < $1.exerciseId }
            .compactMap(record(from:)) ?? []
    }

    /// Reads a scalar source field without exposing DB++'s JSON representation.
    static func sourceString(
        _ exercise: FreeExerciseDBPlusPlus.Exercise,
        _ key: String
    ) -> String? {
        guard case let .string(value)? = exercise.source?[key] else { return nil }
        return value
    }

    /// Reads a string-array source field without exposing DB++'s JSON representation.
    static func sourceStrings(
        _ exercise: FreeExerciseDBPlusPlus.Exercise,
        _ key: String
    ) -> [String] {
        guard case let .array(values)? = exercise.source?[key] else { return [] }
        return values.compactMap { value in
            guard case let .string(string) = value else { return nil }
            return string
        }
    }

    static var setCredits: (direct: Double, indirect: Double, stabilizer: Double) {
        shared?.database.setCredits ?? (direct: 1.0, indirect: 0.5, stabilizer: 0.0)
    }

    static func metadataString(_ key: String) -> String? {
        guard case let .string(value)? = shared?.database.metadata[key] else { return nil }
        return value
    }

    static func metadataInt(_ key: String) -> Int? {
        guard case let .number(value)? = shared?.database.metadata[key] else { return nil }
        return Int(value)
    }

    static var evidencePatterns: [String: EvidencePattern] {
        guard case let .object(evidence)? = shared?.database.metadata["evidence"],
              case let .object(patterns)? = evidence["patterns"]
        else { return [:] }

        return patterns.compactMapValues { value in
            guard case let .object(pattern) = value,
                  case let .string(status)? = pattern["status"],
                  case let .string(summary)? = pattern["summary"]
            else { return nil }
            return EvidencePattern(
                status: status,
                summary: summary,
                references: stringArray(pattern["references"])
            )
        }
    }

    static var evidenceReferences: [String: EvidenceReference] {
        guard case let .object(evidence)? = shared?.database.metadata["evidence"],
              case let .object(references)? = evidence["references"]
        else { return [:] }

        return references.compactMapValues { value in
            guard case let .object(reference) = value,
                  case let .string(title)? = reference["title"],
                  case let .string(type)? = reference["type"],
                  case let .string(url)? = reference["url"]
            else { return nil }
            return EvidenceReference(title: title, type: type, url: url)
        }
    }

    private static func record(
        from exercise: FreeExerciseDBPlusPlus.Exercise
    ) -> ExerciseRecord? {
        guard let name = sourceString(exercise, "name"),
              let category = sourceString(exercise, "category")
        else { return nil }

        return ExerciseRecord(
            exerciseId: exercise.exerciseId,
            name: name,
            force: sourceString(exercise, "force"),
            level: sourceString(exercise, "level"),
            mechanic: sourceString(exercise, "mechanic"),
            equipment: sourceString(exercise, "equipment"),
            primaryMuscles: sourceStrings(exercise, "primaryMuscles"),
            secondaryMuscles: sourceStrings(exercise, "secondaryMuscles"),
            instructions: sourceStrings(exercise, "instructions"),
            category: category,
            images: sourceStrings(exercise, "images"),
            direct: exercise.annotation.direct,
            indirect: exercise.annotation.indirect,
            stabilizers: exercise.annotation.stabilizers,
            patterns: exercise.annotation.patterns,
            volumeEligible: exercise.annotation.volumeEligible,
            confidence: exercise.annotation.confidence
        )
    }

    private static func stringArray(_ value: FreeExerciseDBPlusPlus.JSONValue?) -> [String] {
        guard case let .array(values)? = value else { return [] }
        return values.compactMap { element in
            guard case let .string(value) = element else { return nil }
            return value
        }
    }
}

// MARK: - Request boundary

extension TrainingEngineBridge {
    /// Builds the engine's stable profile from the app's persisted schedule and
    /// equipment vocabulary. DB++ uses the upstream equipment strings, so this
    /// is deliberately the inverse of ImportedExerciseLibrary.equipmentMap.
    static func trainingProfile(
        experience: ExperienceLevel,
        schedule: CoachSchedulePreferences,
        availableEquipment: [Equipment],
        subjectId: String? = nil,
        exercisesPerSession: Int? = nil
    ) -> FreeExerciseDBPlusPlus.TrainingProfile {
        let equipment = availableEquipment
            .flatMap { equipmentStrings(for: $0) }
            .sorted()

        let sessions = Double(schedule.strengthDaysPerWeek)
        let availability = FreeExerciseDBPlusPlus.TrainingAvailability(
            cycleLengthDays: 7,
            sessionsPerCycle: .init(min: sessions, target: sessions, max: sessions),
            exercisesPerSession: exercisesPerSession.map {
                .init(min: Double($0), target: Double($0), max: Double($0))
            },
            preferredDayOffsets: [],
            excludedDayOffsets: [])

        return FreeExerciseDBPlusPlus.TrainingProfile(
            subjectId: subjectId,
            experience: experience.rawValue,
            availability: availability,
            equipment: Array(Set(equipment)).sorted())
    }

    /// Builds a TARGET from the app's per-group MEV/MAV/MRV landmarks. The
    /// canonical MuscleGroup raw value is already DB++'s ontology id.
    static func volumeTarget(
        trackedGroups: Set<MuscleGroup>,
        landmarks: [MuscleGroup: VolumeBands],
        periodDays: Int = 7
    ) -> FreeExerciseDBPlusPlus.VolumeTarget {
        let muscles = trackedGroups
            .sorted { $0.rawValue < $1.rawValue }
            .reduce(into: [String: FreeExerciseDBPlusPlus.TargetRange]()) { result, group in
                guard let bands = landmarks[group] else { return }
                result[group.rawValue] = .init(min: bands.mev, target: bands.mav, max: bands.mrv)
            }

        return FreeExerciseDBPlusPlus.VolumeTarget(
            targetId: "cadence-volume-" + String(periodDays) + "d",
            periodDays: periodDays,
            muscles: muscles)
    }

    /// Convenience overload for the app's standard experience-scaled landmarks.
    static func volumeTarget(
        trackedGroups: Set<MuscleGroup>,
        experience: ExperienceLevel,
        periodDays: Int = 7
    ) -> FreeExerciseDBPlusPlus.VolumeTarget {
        let landmarks = Dictionary(uniqueKeysWithValues: trackedGroups.map {
            ($0, VolumeLandmarks.bands(for: $0, experience: experience))
        })
        return volumeTarget(trackedGroups: trackedGroups, landmarks: landmarks, periodDays: periodDays)
    }

    /// Builds structured intent from app controls. Style is a soft preference:
    /// matching DB++ exercise ids are preferred, while the engine may still use
    /// other eligible movements to satisfy the target.
    static func workoutIntent(
        goal: TrainingGoal,
        environment: String,
        schedule: CoachSchedulePreferences,
        style: SuggestedWorkoutStyle? = nil,
        constraints: FreeExerciseDBPlusPlus.ExerciseConstraints? = nil,
        sessionExerciseCount: Int? = nil
    ) -> FreeExerciseDBPlusPlus.WorkoutIntent {
        let fixedRestDays: [String]
        switch schedule.restPreference {
        case .fixed(let days):
            fixedRestDays = days.sorted { $0.rawValue < $1.rawValue }.map(weekdayName)
        case .rolling:
            fixedRestDays = []
        }

        let engineSchedule = FreeExerciseDBPlusPlus.WorkoutSchedule(
            cycleLengthDays: 7,
            sessionsPerCycle: .init(
                min: schedule.strengthDaysPerWeek,
                target: schedule.strengthDaysPerWeek,
                max: schedule.strengthDaysPerWeek),
            excludedWeekdays: fixedRestDays)

        let preferences = style.map {
            FreeExerciseDBPlusPlus.WorkoutPreferences(
                preferredExerciseIds: preferredExerciseIDs(for: $0))
        }

        return FreeExerciseDBPlusPlus.WorkoutIntent(
            subjectId: nil,
            goal: goal.rawValue,
            requestedGoalPolicy: goal == .endurance ? "general-endurance-v1" : nil,
            environment: environment,
            schedule: engineSchedule,
            sessionConstraints: sessionExerciseCount.map {
                .init(exercisesPerSession: .init(
                    min: $0, target: $0, max: $0))
            },
            exerciseConstraints: constraints,
            preferences: preferences,
            continuity: "preserve")
    }

    private static func equipmentStrings(for equipment: Equipment) -> [String] {
        ImportedExerciseLibrary.equipmentMap
            .filter { $0.value == equipment }
            .map(\.key)
    }

    private static func weekdayName(_ day: Weekday) -> String {
        switch day {
        case .monday: "monday"
        case .tuesday: "tuesday"
        case .wednesday: "wednesday"
        case .thursday: "thursday"
        case .friday: "friday"
        case .saturday: "saturday"
        case .sunday: "sunday"
        }
    }

    static func preferredExerciseIDs(for style: SuggestedWorkoutStyle) -> [String] {
        exerciseRecords
            .filter { record in
                switch style {
                case .fitness:
                    return record.category != "powerlifting"
                        && record.category != "olympic weightlifting"
                        && record.category != "strongman"
                case .bodyweight:
                    return record.equipment?.lowercased() == "body only"
                case .powerlifting:
                    return record.category == "powerlifting"
                case .olympic:
                    return record.category == "olympic weightlifting"
                case .strongman:
                    return record.category == "strongman"
                }
            }
            .map(\.exerciseId)
    }

    /// Runs a typed DB++ operation with a fresh request id and an explicit,
    /// fractional-second ISO-8601 timestamp. The bridge never reads the clock.
    static func run(
        _ operation: FreeExerciseDBPlusPlus.TrainingOperation,
        asOf: Date,
        intent: FreeExerciseDBPlusPlus.WorkoutIntent? = nil,
        profile: FreeExerciseDBPlusPlus.TrainingProfile? = nil,
        target: FreeExerciseDBPlusPlus.VolumeTarget? = nil,
        history: FreeExerciseDBPlusPlus.TrainingHistory? = nil,
        trainingState: FreeExerciseDBPlusPlus.TrainingState? = nil,
        currentPlan: FreeExerciseDBPlusPlus.WorkoutPlan? = nil,
        plan: FreeExerciseDBPlusPlus.WorkoutPlan? = nil,
        historyWindow: FreeExerciseDBPlusPlus.TrainingHistoryWindow = .last28Days
    ) -> FreeExerciseDBPlusPlus.TrainingResult? {
        guard let engine = shared else { return nil }
        let request = FreeExerciseDBPlusPlus.TrainingRequest(
            requestId: UUID().uuidString,
            operation: operation,
            intent: intent,
            profile: profile,
            target: target,
            history: history,
            trainingState: trainingState,
            currentPlan: currentPlan,
            plan: plan,
            asOf: timestampString(asOf),
            historyWindow: historyWindow)
        return try? engine.processTrainingRequest(request)
    }

}

// MARK: - Suggested-workout generation

extension TrainingEngineBridge {
    struct EngineSuggestedWorkout {
        let option: SuggestedWorkoutOption
    }

    /// Generates one style-biased suggestion through DB++ and adapts its
    /// periodized session back into the app's flat suggestion contract.
    static func suggestedWorkout(
        input: SuggestedWorkoutInput,
        context: SuggestedWorkoutEngineContext,
        style: SuggestedWorkoutStyle
    ) -> EngineSuggestedWorkout? {
        let preferredSets = min(4, max(3, input.preferredSetsPerExercise))
        let exerciseLimit = max(1, suggestedWorkoutPlannedSetCap / preferredSets)
        var schedule = context.schedule
        // A suggestion is one launchable workout. The user's weekly schedule
        // still informs the request shape, but does not create duplicate chips.
        schedule.strengthDaysPerWeek = 1

        let profile = trainingProfile(
            experience: context.experience,
            schedule: schedule,
            availableEquipment: context.availableEquipment,
            exercisesPerSession: exerciseLimit)
        let target = fourSetTarget(for: input.trackedGroups)
        let intent = workoutIntent(
            goal: input.trainingGoal,
            environment: context.environment,
            schedule: schedule,
            style: style,
            sessionExerciseCount: exerciseLimit)
        let result = run(
            .generateFromIntent,
            asOf: context.asOf,
            intent: intent,
            profile: profile,
            target: target)
        guard case let .ok(enginePlan) = outcome(for: result, payload: result?.plan),
              let sourceSession = enginePlan.sessions.sorted(by: {
                  ($0.dayOffset, $0.planSessionId) < ($1.dayOffset, $1.planSessionId)
              }).first
        else { return nil }

        let trimmedExercises = trim(
            sourceSession.exercises,
            toSetCap: suggestedWorkoutPlannedSetCap)
        let session = FreeExerciseDBPlusPlus.PlanSession(
            planSessionId: sourceSession.planSessionId,
            phaseId: sourceSession.phaseId,
            dayOffset: sourceSession.dayOffset,
            name: sourceSession.name ?? style.displayName,
            notes: sourceSession.notes,
            exercises: trimmedExercises)
        let trimmedPlan = FreeExerciseDBPlusPlus.WorkoutPlan(
            schemaVersion: enginePlan.schemaVersion,
            planId: enginePlan.planId,
            revisionId: enginePlan.revisionId,
            name: enginePlan.name ?? style.planName,
            description: enginePlan.description,
            provenance: enginePlan.provenance,
            cycle: enginePlan.cycle,
            notes: enginePlan.notes,
            tags: enginePlan.tags,
            phases: enginePlan.phases,
            sessions: [session])
        // `generateFromIntent` already evaluates the generated plan. Re-running
        // the evaluator here doubled chooser latency on device and made the UI
        // smoke readiness assertion race a legitimate, still-running request.
        // The engine's plan is already within the requested exercise/set cap in
        // the normal path. If trimming did occur, use the local contribution
        // fallback below so the gap reflects the actual trimmed plan.
        let evaluation = trimmedExercises.count == sourceSession.exercises.count
            ? result?.evaluation
            : nil

        let exercises = suggestedExercises(
            from: session,
            style: style,
            goal: input.trainingGoal,
            preferredSets: preferredSets)
        guard !exercises.isEmpty else { return nil }
        let initial = deficits(
            trackedGroups: input.trackedGroups,
            completed: input.completedSetsByMuscle)
        let remaining = deficits(
            trackedGroups: input.trackedGroups,
            evaluation: evaluation,
            fallback: initial,
            exercises: exercises)
        let appPlan = WorkoutPlan(
            id: "coach-suggested-\(style.rawValue)",
            name: style.planName,
            source: .coachSuggested,
            scheme: .strength,
            items: exercises.enumerated().map { index, exercise in
                PlanItem(
                    id: index,
                    movement: exercise.name,
                    reps: exercise.repRange.lowerBound,
                    targetSets: exercise.plannedSets)
            },
            notes: "DB++ \(trimmedPlan.planId) revision \(trimmedPlan.revisionId)")
        let option = SuggestedWorkoutOption(
            style: style,
            plan: appPlan,
            exercises: exercises,
            initialDeficits: initial,
            remainingDeficits: remaining,
            plannedSetTotal: exercises.reduce(0) { $0 + $1.plannedSets },
            capTrimmingOccurred: trimmedExercises.count < sourceSession.exercises.count,
            citationIDs: suggestedWorkoutCitationIDs,
            enginePlanID: trimmedPlan.planId,
            engineRevisionID: trimmedPlan.revisionId,
            enginePlanJSON: serialize(trimmedPlan))
        return EngineSuggestedWorkout(option: option)
    }

    private static func fourSetTarget(
        for groups: Set<MuscleGroup>
    ) -> FreeExerciseDBPlusPlus.VolumeTarget {
        let landmarks = Dictionary(uniqueKeysWithValues: groups.map {
            ($0, VolumeBands(mev: Double(suggestedWorkoutTargetSetsPerGroup),
                             mav: Double(suggestedWorkoutTargetSetsPerGroup),
                             mrv: Double(suggestedWorkoutTargetSetsPerGroup)))
        })
        return volumeTarget(trackedGroups: groups, landmarks: landmarks, periodDays: 7)
    }

    private static func trim(
        _ exercises: [FreeExerciseDBPlusPlus.PlanExercisePrescription],
        toSetCap cap: Int
    ) -> [FreeExerciseDBPlusPlus.PlanExercisePrescription] {
        var total = 0
        return exercises.sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }.filter { exercise in
            let sets = max(1, integerValue(exercise.sets) ?? exercise.plannedSets?.count ?? 1)
            guard total + sets <= cap else { return false }
            total += sets
            return true
        }
    }

    private static func suggestedExercises(
        from session: FreeExerciseDBPlusPlus.PlanSession,
        style: SuggestedWorkoutStyle,
        goal: TrainingGoal,
        preferredSets: Int
    ) -> [SuggestedWorkoutExercise] {
        let styleIDs = Set(preferredExerciseIDs(for: style))
        let credits = setCredits
        return session.exercises.sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }.compactMap { prescription in
            let record = prescription.exerciseId.flatMap { id in
                exerciseRecords.first { $0.exerciseId == id }
            }
            guard record != nil || prescription.exerciseName != nil else { return nil }
            let name = record?.name ?? prescription.exerciseName ?? "Exercise"
            let sets = max(1, integerValue(prescription.sets)
                ?? prescription.plannedSets?.count
                ?? preferredSets)
            let reps = repRange(prescription.reps)
            let repLadder = prescription.plannedSets?.compactMap { integerValue($0.reps) } ?? []
            let lower = repLadder.min() ?? reps.lower ?? goal.repRange.lowerBound
            let upper = repLadder.max() ?? reps.upper ?? goal.repRange.upperBound
            let direct = record?.direct ?? []
            let indirect = record?.indirect ?? []
            let stabilizers = record?.stabilizers ?? []
            var contributions: [SuggestedMuscleContribution] = []
            for muscle in direct {
                contributions.append(.init(
                    muscleID: muscle,
                    weight: credits.direct,
                    plannedSetContribution: Double(sets) * credits.direct))
            }
            for muscle in indirect where !direct.contains(muscle) {
                contributions.append(.init(
                    muscleID: muscle,
                    weight: credits.indirect,
                    plannedSetContribution: Double(sets) * credits.indirect))
            }
            for muscle in stabilizers
                where !direct.contains(muscle) && !indirect.contains(muscle) && credits.stabilizer > 0 {
                contributions.append(.init(
                    muscleID: muscle,
                    weight: credits.stabilizer,
                    plannedSetContribution: Double(sets) * credits.stabilizer))
            }
            guard !contributions.isEmpty else { return nil }
            let score = contributions.reduce(0) { $0 + $1.plannedSetContribution }
            return SuggestedWorkoutExercise(
                candidateID: record?.exerciseId ?? prescription.exerciseId ?? name,
                name: name,
                mechanics: record?.mechanic.flatMap(Mechanics.init(rawValue:)) ?? .compound,
                plannedSets: sets,
                repRange: lower...max(lower, upper),
                contributions: contributions,
                selectionScore: score,
                isInStyle: prescription.exerciseId.map(styleIDs.contains) ?? false)
        }
    }

    private static func deficits(
        trackedGroups: Set<MuscleGroup>,
        completed: [String: Double]
    ) -> [String: Double] {
        trackedGroups.reduce(into: [:]) { result, group in
            result[group.rawValue] = max(
                0,
                Double(suggestedWorkoutTargetSetsPerGroup) - (completed[group.rawValue] ?? 0))
        }
    }

    private static func deficits(
        trackedGroups: Set<MuscleGroup>,
        evaluation: FreeExerciseDBPlusPlus.PlanEvaluation?,
        fallback: [String: Double],
        exercises: [SuggestedWorkoutExercise]
    ) -> [String: Double] {
        guard let evaluation else {
            var remaining = fallback
            for exercise in exercises {
                for contribution in exercise.contributions where remaining[contribution.muscleID] != nil {
                    remaining[contribution.muscleID] = max(
                        0,
                        (remaining[contribution.muscleID] ?? 0) - contribution.plannedSetContribution)
                }
            }
            return remaining
        }
        return trackedGroups.reduce(into: [:]) { result, group in
            let row = evaluation.muscleCoverage[group.rawValue]
            let target = row?.target ?? Double(suggestedWorkoutTargetSetsPerGroup)
            let actual = row?.actualEffectiveSets ?? row?.plannedSets ?? 0
            result[group.rawValue] = max(0, target - actual)
        }
    }
}

// MARK: - Result boundary

extension TrainingEngineBridge {
    /// Converts one engine session into the app's existing recommendation shape.
    static func recommendedExercises(
        from session: FreeExerciseDBPlusPlus.PlanSession
    ) -> [CoachSession.RecommendedExercise] {
        session.exercises.sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }.compactMap { prescription in
            let exercise = prescription.exerciseId.flatMap { id in
                try? shared?.database.getExercise(id)
            }
            guard exercise != nil || prescription.exerciseName != nil else { return nil }

            let plannedSets = prescription.plannedSets ?? []
            let repValues = plannedSets.compactMap { integerValue($0.reps) }
            let reps = repRange(prescription.reps)
            let ladder = repValues.isEmpty ? nil : repValues
            let sets = plannedSets.isEmpty
                ? integerValue(prescription.sets)
                : plannedSets.count
            let load = numericValue(prescription.load)
                ?? plannedSets.compactMap { numericValue($0.load) }.first
            let effort = integerValue(prescription.effort)
                ?? plannedSets.compactMap { integerValue($0.effort) }.first

            return CoachSession.RecommendedExercise(
                name: exercise.flatMap { sourceString($0, "name") } ?? prescription.exerciseName ?? "Exercise",
                primaryMuscles: exercise?.annotation.direct ?? [],
                sets: sets,
                repsLow: ladder?.min() ?? reps.lower,
                repsHigh: ladder?.max() ?? reps.upper,
                loadKg: load,
                rir: effort,
                repLadder: ladder)
        }
    }

    /// Converts the periodized engine plan into the app's calendar-shaped plan.
    /// Sessions sharing a day offset remain separate chips on the same day.
    static func weeklyPlan(
        from plan: FreeExerciseDBPlusPlus.WorkoutPlan,
        startingOn: Date
    ) -> WeeklyPlan {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startingOn)
        let sessionsByOffset = Dictionary(grouping: plan.sessions, by: \.dayOffset)
        let days = sessionsByOffset.keys.sorted().map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let sessions = (sessionsByOffset[offset] ?? []).sorted {
                $0.planSessionId < $1.planSessionId
            }.map { engineSession in
                PlannedSession(
                    id: "\\(plan.planId)-\\(engineSession.planSessionId)",
                    kind: .strength,
                    label: engineSession.name ?? "Strength",
                    isHard: true,
                    isRest: false,
                    exercises: recommendedExercises(from: engineSession))
            }
            return WeeklyPlan.DayOutline(
                date: date,
                label: sessions.map(\.label).joined(separator: " · "),
                sessions: sessions,
                isToday: calendar.isDate(date, inSameDayAs: startingOn),
                isCompleted: false,
                isFuture: date > start,
                isPast: date < start)
        }
        return WeeklyPlan(days: days, generatedAt: startingOn)
    }

    /// Serializes the package plan interchange document for additive app
    /// persistence and later re-evaluation/adaptation.
    static func serialize(
        _ plan: FreeExerciseDBPlusPlus.WorkoutPlan
    ) -> Data? {
        try? JSONEncoder().encode(plan)
    }

    static func deserializePlan(
        _ data: Data
    ) -> FreeExerciseDBPlusPlus.WorkoutPlan? {
        try? JSONDecoder().decode(FreeExerciseDBPlusPlus.WorkoutPlan.self, from: data)
    }

    /// The only explicit rejection seam for a future intent front-end. A
    /// result with an expected payload is successful for its operation-specific
    /// status, while status text alone is never treated as generic success.
    static func outcome<T>(
        for result: FreeExerciseDBPlusPlus.TrainingResult?,
        payload: T?
    ) -> EngineOutcome<T> {
        guard let result else { return .unavailable }
        if result.status == "needs_clarification" {
            return .needsInput(result.missingInformation)
        }
        if result.status == "unsatisfiable" || result.status.hasPrefix("invalid") {
            return .unsatisfiable(result.issues)
        }
        guard let payload else { return .unavailable }
        return .ok(payload)
    }

    private static func repRange(
        _ value: FreeExerciseDBPlusPlus.JSONValue?
    ) -> (lower: Int?, upper: Int?) {
        guard case let .object(object)? = value else {
            let scalar = integerValue(value)
            return (scalar, scalar)
        }
        let target = integerValue(object["target"])
        let lower = integerValue(object["min"]) ?? target ?? integerValue(object["max"])
        let upper = integerValue(object["max"]) ?? target ?? integerValue(object["min"])
        return (lower, upper)
    }

    private static func integerValue(_ value: FreeExerciseDBPlusPlus.JSONValue?) -> Int? {
        numericValue(value).map { Int($0.rounded()) }
    }

    private static func numericValue(_ value: FreeExerciseDBPlusPlus.JSONValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .number(let number): return number
        case .string(let string): return Double(string)
        case .array(let values): return values.lazy.compactMap(numericValue).first
        case .object(let object):
            for key in ["target", "value", "rir", "kg", "min", "max"] {
                if let number = numericValue(object[key]) { return number }
            }
            return nil
        case .null, .bool:
            return nil
        }
    }
}

enum EngineOutcome<T> {
    case ok(T)
    case needsInput([FreeExerciseDBPlusPlus.MissingInformation])
    case unsatisfiable([FreeExerciseDBPlusPlus.PlanIssue])
    case unavailable
}

// MARK: - Observation and adaptive coaching

extension TrainingEngineBridge {
    /// Builds the DB++ ACTUAL history from finalized app sessions. The workout
    /// interchange schema is pinned by DB++'s bundled `workout.schema.json`;
    /// version 0.3.0 is the current released schema and supports the app's
    /// optional plan linkage and per-set RPE/load fields.
    static func trainingHistory(
        from sessions: [WorkoutSession],
        plans suppliedPlans: [FreeExerciseDBPlusPlus.WorkoutPlan] = [],
        subjectId: String
    ) -> FreeExerciseDBPlusPlus.TrainingHistory {
        let liveSessions = sessions
            .filter { $0.deletedAt == nil && ($0.endedAt != nil || $0.isLogged) }
            .sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }

        let sessionPlans = liveSessions.compactMap { session -> FreeExerciseDBPlusPlus.WorkoutPlan? in
            guard let data = session.enginePlanJSON else { return nil }
            return deserializePlan(data)
        }
        let plans = uniquePlans(suppliedPlans + sessionPlans)
        let workouts = liveSessions.map { workout(from: $0, plans: plans) }
        let activations = plans.compactMap { plan -> FreeExerciseDBPlusPlus.PlanActivation? in
            let start = liveSessions.first {
                $0.enginePlanId == plan.planId && $0.engineRevisionId == plan.revisionId
            }?.date
            guard let start else { return nil }
            return FreeExerciseDBPlusPlus.PlanActivation(
                planId: plan.planId,
                revisionId: plan.revisionId,
                effectiveFrom: timestampString(start))
        }

        return FreeExerciseDBPlusPlus.TrainingHistory(
            subjectId: subjectId,
            plans: plans,
            workouts: workouts,
            planActivations: activations)
    }

    /// Derives the seven-day observation surface used by Home. A separate
    /// 28-day state is requested for adaptation below because the released
    /// coaching policy intentionally reasons over longer performance history.
    public static func observationSnapshot(
        from sessions: [WorkoutSession],
        trackedGroups: Set<MuscleGroup>,
        experience: ExperienceLevel,
        subjectId: String,
        asOf: Date
    ) -> EngineObservationSnapshot? {
        let target = volumeTarget(trackedGroups: trackedGroups, experience: experience)
        let history = trainingHistory(from: sessions, subjectId: subjectId)
        return observationSnapshot(
            history: history,
            target: target,
            asOf: asOf)
    }

    /// Encodes the model extraction boundary so Home can perform the engine
    /// work off the main actor without moving SwiftData models across actors.
    public static func historyData(
        from sessions: [WorkoutSession],
        subjectId: String
    ) -> Data? {
        try? JSONEncoder().encode(trainingHistory(from: sessions, subjectId: subjectId))
    }

    /// Background-safe counterpart to the model-based observation entry point.
    public static func observationSnapshot(
        historyData: Data,
        trackedGroups: Set<MuscleGroup>,
        experience: ExperienceLevel,
        asOf: Date
    ) -> EngineObservationSnapshot? {
        guard let history = try? JSONDecoder().decode(
            FreeExerciseDBPlusPlus.TrainingHistory.self,
            from: historyData)
        else { return nil }
        let target = volumeTarget(trackedGroups: trackedGroups, experience: experience)
        return observationSnapshot(history: history, target: target, asOf: asOf)
    }

    private static func observationSnapshot(
        history: FreeExerciseDBPlusPlus.TrainingHistory,
        target: FreeExerciseDBPlusPlus.VolumeTarget,
        asOf: Date
    ) -> EngineObservationSnapshot? {
        // DB++ history is intentionally finalized-workout history. Preserve the
        // app's live/in-progress presentation by letting the caller fall back to
        // its existing facts until at least one completed workout is available.
        guard !history.workouts.isEmpty else { return nil }
        guard let result = run(
            .deriveState,
            asOf: asOf,
            target: target,
            history: history,
            historyWindow: .last7Days),
            let state = result.trainingState,
            result.status == "state_derived"
        else { return nil }
        return observationSnapshot(from: state, asOf: asOf)
    }

    /// Produces the engine-backed strength session that is composed behind the
    /// existing `CoachSession` façade. The caller still owns readiness and
    /// eligibility, so this method returns only an engine proposal.
    public static func adaptiveCoachSession(
        from sessions: [WorkoutSession],
        schedule: CoachSchedulePreferences,
        goal: TrainingGoal,
        experience: ExperienceLevel,
        subjectId: String,
        asOf: Date,
        facts: CoachFacts? = nil
    ) -> CoachSession? {
        let history = trainingHistory(from: sessions, subjectId: subjectId)
        let currentPlan = currentEnginePlan(from: sessions)
        return adaptiveCoachSession(
            history: history,
            currentPlan: currentPlan,
            schedule: schedule,
            goal: goal,
            experience: experience,
            subjectId: subjectId,
            asOf: asOf,
            facts: facts)
    }

    /// Background-safe counterpart to the model-based adaptive entry point.
    public static func adaptiveCoachSession(
        historyData: Data,
        schedule: CoachSchedulePreferences,
        goal: TrainingGoal,
        experience: ExperienceLevel,
        subjectId: String,
        asOf: Date
    ) -> CoachSession? {
        guard let history = try? JSONDecoder().decode(
            FreeExerciseDBPlusPlus.TrainingHistory.self,
            from: historyData)
        else { return nil }
        return adaptiveCoachSession(
            history: history,
            currentPlan: currentEnginePlan(from: history),
            schedule: schedule,
            goal: goal,
            experience: experience,
            subjectId: subjectId,
            asOf: asOf)
    }

    private static func adaptiveCoachSession(
        history: FreeExerciseDBPlusPlus.TrainingHistory,
        currentPlan: FreeExerciseDBPlusPlus.WorkoutPlan?,
        schedule: CoachSchedulePreferences,
        goal: TrainingGoal,
        experience: ExperienceLevel,
        subjectId: String,
        asOf: Date,
        facts: CoachFacts? = nil
    ) -> CoachSession? {
        var coachSchedule = schedule
        // The Coach card proposes one launchable session. The user's weekly
        // frequency still informs the target, but asking generation for a
        // two-session cycle with a one-session exercise budget can be
        // over-constrained for a single tracked group.
        coachSchedule.strengthDaysPerWeek = 1
        let exerciseCount = min(6, max(4, schedule.trackedMuscleGroups.count))
        let profile = trainingProfile(
            experience: experience,
            schedule: coachSchedule,
            availableEquipment: Equipment.allCases,
            subjectId: subjectId,
            exercisesPerSession: exerciseCount)
        let target = volumeTarget(
            trackedGroups: schedule.trackedMuscleGroups,
            experience: experience)
        let stateResult = run(
            .deriveState,
            asOf: asOf,
            target: target,
            history: history)
        guard let state = stateResult?.trainingState else { return nil }

        // Phase 4 adapts an active engine plan. A user with no materialised
        // engine plan is still fully supported by the Phase 3 suggestion flow;
        // generating a second hidden plan here would duplicate work and make
        // the Home snapshot needlessly expensive.
        guard let currentPlan else { return nil }

        let adaptation = run(
            .adaptPlan,
            asOf: asOf,
            profile: profile,
            target: target,
            history: history,
            trainingState: state,
            currentPlan: currentPlan)?.adaptation
        let adaptedPlan = adaptation?.proposedPlan ?? currentPlan
        let adaptationDecisions = adaptation?.decisions ?? []
        let progression = run(
            .suggestProgression,
            asOf: asOf,
            trainingState: state,
            plan: adaptedPlan)?.coachDecisions ?? []
        let decisions = adaptationDecisions + progression

        guard let proposal = session(
            from: adaptedPlan,
            decisions: decisions,
            goal: goal,
            asOf: asOf)
        else { return nil }

        // Recovery and same-lift/pattern/body-part rules remain authoritative.
        // If they reject the engine's first proposal, regenerate once with the
        // offending catalog exercise ids excluded so the engine can choose a
        // compliant alternative instead of silently weakening the app gate.
        guard let facts else { return proposal }
        guard case .eligible = SessionEligibilityPolicy.evaluate(proposal, facts: facts)
        else {
            let excluded = proposal.exercises?.compactMap { exercise in
                exerciseRecords.first { record in
                    record.name.caseInsensitiveCompare(exercise.name) == .orderedSame
                }?.exerciseId
            } ?? []
            guard !excluded.isEmpty,
                  let alternatePlan = generatedCoachPlan(
                      goal: goal,
                      schedule: coachSchedule,
                      experience: experience,
                      profile: profile,
                      target: target,
                      asOf: asOf,
                      excludedExerciseIDs: excluded,
                      sessionExerciseCount: exerciseCount),
                  let alternate = session(
                      from: alternatePlan,
                      decisions: [],
                      goal: goal,
                      asOf: asOf),
                  case .eligible = SessionEligibilityPolicy.evaluate(alternate, facts: facts)
            else { return nil }
            return alternate
        }
        return proposal
    }

    private static func observationSnapshot(
        from state: FreeExerciseDBPlusPlus.TrainingState,
        asOf: Date
    ) -> EngineObservationSnapshot {
        let effectiveSets = state.muscleState.reduce(into: [String: Double]()) { result, pair in
            guard case let .object(row) = pair.value,
                  case let .number(value)? = row["effectiveSets"]
            else { return }
            result[pair.key] = value
        }
        let unplannedSets: Int = {
            guard case let .number(value)? = state.adherenceState["unplannedSets"] else { return 0 }
            return Int(value.rounded())
        }()
        let substitutionCompletion: Double = {
            guard case let .number(value)? = state.adherenceState["substitutionAdjustedCompletion"] else { return 0 }
            return value
        }()
        return EngineObservationSnapshot(
            subjectId: state.subjectId,
            asOf: asOf,
            stateVersion: state.stateVersion,
            effectiveSetsByMuscle: effectiveSets,
            unplannedSets: unplannedSets,
            substitutionAdjustedCompletion: substitutionCompletion)
    }

    private static func workout(
        from session: WorkoutSession,
        plans: [FreeExerciseDBPlusPlus.WorkoutPlan]
    ) -> FreeExerciseDBPlusPlus.Workout {
        let plan = plans.first {
            $0.planId == session.enginePlanId && $0.revisionId == session.engineRevisionId
        }
        let planSession = plan?.sessions.sorted {
            ($0.dayOffset, $0.planSessionId) < ($1.dayOffset, $1.planSessionId)
        }.first { engineSession in
            session.exercisesInOrder.contains { appExercise in
                engineSession.exercises.contains { prescription in
                    prescription.exerciseId == appExercise.sourceExerciseID
                        || prescription.exerciseName?.caseInsensitiveCompare(appExercise.name) == .orderedSame
                }
            }
        }
        let reference = plan.map {
            FreeExerciseDBPlusPlus.PlanReference(
                planId: $0.planId,
                revisionId: $0.revisionId,
                planSessionId: planSession?.planSessionId)
        }
        let observations = exerciseObservations(from: session, planSession: planSession)
        return FreeExerciseDBPlusPlus.Workout(
            schemaVersion: "0.3.0",
            sessionId: session.id.uuidString,
            startTime: timestampString(session.date),
            endTime: session.endedAt.map(timestampString),
            exercises: observations,
            planReference: reference)
    }

    private static func exerciseObservations(
        from session: WorkoutSession,
        planSession: FreeExerciseDBPlusPlus.PlanSession?
    ) -> [FreeExerciseDBPlusPlus.ExerciseObservation] {
        let ownerSets = session.orderedSets.filter { $0.isOwnerSet }
        var grouped: [(exercise: Exercise, sets: [SetEntry])] = []
        var indices: [UUID: Int] = [:]
        for set in ownerSets {
            guard let exercise = set.exercise else { continue }
            if let index = indices[exercise.id] {
                grouped[index].sets.append(set)
            } else {
                indices[exercise.id] = grouped.count
                grouped.append((exercise, [set]))
            }
        }

        return grouped.enumerated().map { index, group in
            let prescription = planSession?.exercises.first {
                $0.exerciseId == group.exercise.sourceExerciseID
                    || $0.exerciseName?.caseInsensitiveCompare(group.exercise.name) == .orderedSame
            }
            let observations = group.sets.enumerated().map { setIndex, set in
                FreeExerciseDBPlusPlus.SetObservation(
                    setNumber: setIndex + 1,
                    setType: set.isWarmup ? "warmup" : "working",
                    setPrescriptionId: prescription?.plannedSets?.indices.contains(setIndex) == true
                        ? prescription?.plannedSets?[setIndex].setPrescriptionId : nil,
                    reps: set.reps > 0 ? set.reps : nil,
                    load: set.effectiveLoadKg > 0
                        ? .init(value: set.effectiveLoadKg, unit: "kg") : nil,
                    completed: !set.isWarmup && set.reps > 0,
                    rpe: set.rpe,
                    rir: set.rpe.map { max(0, 10 - $0) })
            }
            return FreeExerciseDBPlusPlus.ExerciseObservation(
                exerciseId: group.exercise.sourceExerciseID,
                exerciseName: group.exercise.name,
                order: index + 1,
                sets: observations,
                exercisePrescriptionId: prescription?.prescriptionId)
        }
    }

    private static func uniquePlans(
        _ plans: [FreeExerciseDBPlusPlus.WorkoutPlan]
    ) -> [FreeExerciseDBPlusPlus.WorkoutPlan] {
        var seen = Set<String>()
        return plans
            .sorted { ($0.planId, $0.revisionId) < ($1.planId, $1.revisionId) }
            .filter { seen.insert("\($0.planId)|\($0.revisionId)").inserted }
    }

    private static func currentEnginePlan(
        from sessions: [WorkoutSession]
    ) -> FreeExerciseDBPlusPlus.WorkoutPlan? {
        sessions
            .filter { $0.deletedAt == nil && $0.enginePlanJSON != nil }
            .sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }
            .compactMap { $0.enginePlanJSON.flatMap(deserializePlan) }
            .first
    }

    private static func currentEnginePlan(
        from history: FreeExerciseDBPlusPlus.TrainingHistory
    ) -> FreeExerciseDBPlusPlus.WorkoutPlan? {
        if let activation = history.planActivations.max(by: {
            $0.effectiveFrom < $1.effectiveFrom
        }), let plan = history.plan(
            planId: activation.planId, revisionId: activation.revisionId) {
            return plan
        }
        return history.plans.sorted {
            ($0.planId, $0.revisionId) < ($1.planId, $1.revisionId)
        }.last
    }

    private static func generatedCoachPlan(
        goal: TrainingGoal,
        schedule: CoachSchedulePreferences,
        experience: ExperienceLevel,
        profile: FreeExerciseDBPlusPlus.TrainingProfile,
        target: FreeExerciseDBPlusPlus.VolumeTarget,
        asOf: Date,
        excludedExerciseIDs: [String] = [],
        sessionExerciseCount: Int? = nil
    ) -> FreeExerciseDBPlusPlus.WorkoutPlan? {
        let constraints = excludedExerciseIDs.isEmpty ? nil : FreeExerciseDBPlusPlus.ExerciseConstraints(
            excludedExerciseIds: excludedExerciseIDs.sorted())
        let intent = workoutIntent(
            goal: goal,
            environment: "commercial_gym",
            schedule: schedule,
            constraints: constraints,
            sessionExerciseCount: sessionExerciseCount ?? min(6, max(1, schedule.trackedMuscleGroups.count)))
        let result = run(
            .generateFromIntent,
            asOf: asOf,
            intent: intent,
            profile: profile,
            target: target)
        guard case let .ok(plan) = outcome(for: result, payload: result?.plan) else { return nil }
        return plan
    }

    private static func session(
        from plan: FreeExerciseDBPlusPlus.WorkoutPlan,
        decisions: [FreeExerciseDBPlusPlus.CoachDecision],
        goal: TrainingGoal,
        asOf: Date
    ) -> CoachSession? {
        guard let engineSession = plan.sessions.sorted(by: {
            ($0.dayOffset, $0.planSessionId) < ($1.dayOffset, $1.planSessionId)
        }).first else { return nil }
        let exercises = recommendedExercises(from: engineSession)
        guard !exercises.isEmpty else { return nil }

        let decisionTypes = decisions.map(\.decisionType).filter { $0 != "hold" && $0 != "insufficient_data" }
        let subtitle: String
        if decisionTypes.isEmpty {
            subtitle = "\(goal.repRange.lowerBound)–\(goal.repRange.upperBound) reps · engine plan"
        } else {
            subtitle = "Engine \(decisionTypes.joined(separator: ", ")) · \(goal.targetRIR) RIR target"
        }
        return CoachSession(
            id: "engine.\(plan.planId).\(plan.revisionId)",
            kind: .strength,
            title: engineSession.name ?? plan.name ?? "Strength session",
            subtitle: subtitle,
            durationMinutes: 45,
            exercises: exercises,
            trainingLoadTags: ["strength", "engine"] + decisionTypes,
            citationIds: engineCitationIDs(
                for: engineSession,
                plan: plan,
                decisions: decisions,
                goal: goal),
            launchPayload: .strengthPlan(plan.planId),
            systemsTrained: [.maximalStrength, .hypertrophy],
            evidenceCategory: .strengthIntensity)
    }

    /// Resolves the evidence actually attached to an engine prescription into
    /// the app's citation contract. DB++ stores movement references indirectly:
    /// a prescription points to an exercise, the exercise points to pattern ids,
    /// and the bundled evidence metadata maps each pattern to references. The
    /// raw pattern ids never cross into a CoachSession or the UI.
    private static func engineCitationIDs(
        for engineSession: FreeExerciseDBPlusPlus.PlanSession,
        plan: FreeExerciseDBPlusPlus.WorkoutPlan,
        decisions: [FreeExerciseDBPlusPlus.CoachDecision],
        goal: TrainingGoal
    ) -> [String] {
        var ids = suggestedWorkoutCitationIDs
        ids.append(contentsOf: CitationRegistry.strengthIntensityPool.citationIds)
        if goal == .hypertrophy {
            ids.append(contentsOf: CitationRegistry.strengthVolumePool.citationIds)
        }
        if !(plan.phases ?? []).isEmpty {
            ids.append(contentsOf: CitationRegistry.periodizationPool.citationIds)
        }

        for prescription in engineSession.exercises {
            guard let record = exerciseRecord(for: prescription) else { continue }
            for patternID in record.patterns.sorted() {
                ids.append(contentsOf: evidencePatterns[patternID]?.references.map {
                    "exdb.\($0)"
                } ?? [])
            }
        }

        let progressionTypes = Set(decisions.map(\.decisionType))
        if !progressionTypes.isDisjoint(with: [
            "increase_load", "decrease_load", "increase_reps", "decrease_reps"
        ]) {
            ids.append(CitationRegistry.rpeAutoregulation.id)
        }
        if !progressionTypes.isDisjoint(with: ["increase_sets", "decrease_sets"]) {
            ids.append(contentsOf: CitationRegistry.strengthVolumePool.citationIds)
        }

        var seen: Set<String> = []
        return ids.filter { id in
            CitationRegistry.citation(forId: id) != nil && seen.insert(id).inserted
        }
    }

    private static func exerciseRecord(
        for prescription: FreeExerciseDBPlusPlus.PlanExercisePrescription
    ) -> ExerciseRecord? {
        if let exerciseId = prescription.exerciseId,
           let record = exerciseRecords.first(where: { $0.exerciseId == exerciseId }) {
            return record
        }
        guard let exerciseName = prescription.exerciseName else { return nil }
        return exerciseRecords.first {
            $0.name.caseInsensitiveCompare(exerciseName) == .orderedSame
        }
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
