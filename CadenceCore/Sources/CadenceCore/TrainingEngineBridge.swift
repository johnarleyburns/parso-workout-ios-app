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
        currentPlan: FreeExerciseDBPlusPlus.WorkoutPlan? = nil,
        plan: FreeExerciseDBPlusPlus.WorkoutPlan? = nil
    ) -> FreeExerciseDBPlusPlus.TrainingResult? {
        guard let engine = shared else { return nil }
        let request = FreeExerciseDBPlusPlus.TrainingRequest(
            requestId: UUID().uuidString,
            operation: operation,
            intent: intent,
            profile: profile,
            target: target,
            history: history,
            currentPlan: currentPlan,
            plan: plan,
            asOf: timestampString(asOf),
            historyWindow: .last28Days)
        return try? engine.processTrainingRequest(request)
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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
        let evaluation = run(
            .evaluatePlan,
            asOf: context.asOf,
            profile: profile,
            target: target,
            plan: trimmedPlan)?.evaluation

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
