import Foundation

public let suggestedWorkoutCitationIDs = [
    "iversenTimeEfficient2021",
    "pellandFractionalSets2024",
    // The direct/indirect credit split is stated in the About sheet, so it cites.
    "pellandDoseResponse2026",
]

public struct SuggestedExerciseCandidate: Equatable, Sendable {
    public let id: String
    public let name: String
    public let mechanics: Mechanics
    public let primaryMuscles: [String]
    public let secondaryMuscles: [String]
    /// Explicit equipment is a stronger style boundary than a legacy modality
    /// tag. Older stores can carry incomplete modality facets.
    public let equipment: Equipment?
    /// False for stretching, plyometrics and cardio: such a movement can never be
    /// suggested as strength work, whatever muscles it lists (decision D3).
    public let volumeEligible: Bool
    public let trainingTypes: [ExerciseTrainingType]
    public let modalities: [ExerciseModality]
    public let sportContexts: [ExerciseSportContext]
    /// Marks a catalog movement that the app has observed in this user's
    /// completed history. Used only by the Personalized chooser option.
    public let isPersonalized: Bool

    public init(id: String, name: String, mechanics: Mechanics,
                primaryMuscles: [String], secondaryMuscles: [String] = [],
                equipment: Equipment? = nil,
                volumeEligible: Bool = true,
                trainingTypes: [ExerciseTrainingType] = [.strength],
                modalities: [ExerciseModality] = [],
                sportContexts: [ExerciseSportContext] = [.generalFitness],
                isPersonalized: Bool = false) {
        self.id = id
        self.name = name
        self.mechanics = mechanics
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.volumeEligible = volumeEligible
        self.trainingTypes = trainingTypes
        self.modalities = modalities
        self.sportContexts = sportContexts
        self.isPersonalized = isPersonalized
    }

    /// Builds the value sent to the suggestion engine from the canonical
    /// in-memory catalog. The app uses this as a safe fallback while an existing
    /// SwiftData store is still seeding or when an older store has unusable
    /// exercise facets.
    public init(template: ExerciseTemplate) {
        self.init(id: ExerciseSuggestionExclusionKey.forTemplate(template),
                  name: template.name,
                  mechanics: template.mechanics,
                  primaryMuscles: template.primaryMuscles,
                  secondaryMuscles: template.secondaryMuscles,
                  equipment: template.equipment,
                  volumeEligible: template.volumeEligible,
                  trainingTypes: template.trainingTypes,
                  modalities: template.modalities,
                  sportContexts: template.sportContexts)
    }

    /// Whether this movement belongs to a training style's own pool.
    public func matches(_ style: SuggestedWorkoutStyle) -> Bool {
        let isOlympicOnly = trainingTypes.contains(.olympicWeightlifting)
            || ExerciseTrainingType.isOlympicOnlyMovement(named: name)
        switch style {
        case .fitness:
            return trainingTypes.contains(.strength)
                && !isOlympicOnly
                && sportContexts == [.generalFitness]
        case .personalized:
            return isPersonalized
        case .bodyweight:
            return equipment == .bodyweight
                || (equipment == nil && modalities.contains(.bodyweight))
        case .powerlifting:
            return trainingTypes.contains(.powerlifting)
        case .olympic:
            return trainingTypes.contains(.olympicWeightlifting)
        case .strongman:
            return trainingTypes.contains(.strongman)
        }
    }
}

/// The kind of training a suggested workout is built from.
///
/// This replaced the minimum / medium / maximal tiers (DB++ adoption, decision
/// D6). Those were the same algorithm at 4, 8 and 12 sets per muscle, so they
/// differed only in how much of one ordering survived the cap — the user was
/// choosing between three lengths of the same workout. Every style now uses the
/// same minimum target, and what varies is the movements, which is what actually
/// differs between training populations.
public enum SuggestedWorkoutStyle: String, CaseIterable, Equatable, Sendable {
    case personalized, fitness, bodyweight, powerlifting, olympic, strongman

    public var displayName: String {
        switch self {
        case .personalized: "Personalized"
        case .fitness: "Fitness"
        case .bodyweight: "Bodyweight"
        case .powerlifting: "Powerlifting"
        case .olympic: "Olympic Weightlifting"
        case .strongman: "Strongman"
        }
    }

    public var planName: String { "\(displayName) Plan" }

    public var subtitle: String {
        switch self {
        case .personalized: "History-first movements, with your preferred style filling any gaps."
        case .fitness: "General gym movements — machines, cables and free weights."
        case .bodyweight: "No equipment — movements you load with your own body."
        case .powerlifting: "Squat, bench and deadlift variations and their accessories."
        case .olympic: "Snatch, clean and jerk variations, pulls and squats."
        case .strongman: "Carries, loads, drags and odd-object lifts."
        }
    }
}

/// Weekly sets per tracked muscle group every style aims at.
public let suggestedWorkoutTargetSetsPerGroup = 4
/// Total planned sets a single suggestion may prescribe.
public let suggestedWorkoutPlannedSetCap = 20

/// How much completed strength history the suggestion can use. A limited or
/// unavailable history is a warning, never a reason to block generation.
public enum SuggestedWorkoutHistoryQuality: Equatable, Sendable {
    case sufficient
    case limited(workoutCount: Int, workingSetCount: Int)
    case unavailable
}

public struct SuggestedMuscleContribution: Equatable, Sendable {
    public let muscleID: String
    public let weight: Double
    public let plannedSetContribution: Double

    public init(muscleID: String, weight: Double, plannedSetContribution: Double) {
        self.muscleID = muscleID
        self.weight = weight
        self.plannedSetContribution = plannedSetContribution
    }
}

public struct SuggestedWorkoutExercise: Equatable, Sendable {
    public let candidateID: String
    public let name: String
    public let mechanics: Mechanics
    public let plannedSets: Int
    public let repRange: ClosedRange<Int>
    public let contributions: [SuggestedMuscleContribution]
    public let selectionScore: Double
    /// True when the movement came from the chosen style's own pool rather than
    /// the general strength fallback.
    public let isInStyle: Bool

    public init(candidateID: String, name: String, mechanics: Mechanics, plannedSets: Int,
                repRange: ClosedRange<Int>, contributions: [SuggestedMuscleContribution],
                selectionScore: Double, isInStyle: Bool = true) {
        self.candidateID = candidateID
        self.name = name
        self.mechanics = mechanics
        self.plannedSets = plannedSets
        self.repRange = repRange
        self.contributions = contributions
        self.selectionScore = selectionScore
        self.isInStyle = isInStyle
    }
}

public struct SuggestedWorkoutOption: Equatable, Sendable {
    public let style: SuggestedWorkoutStyle
    public let plan: WorkoutPlan
    public let exercises: [SuggestedWorkoutExercise]
    public let initialDeficits: [String: Double]
    public let remainingDeficits: [String: Double]
    public let plannedSetTotal: Int
    public let capTrimmingOccurred: Bool
    public let citationIDs: [String]
    /// DB++ provenance carried with a generated suggestion so materialising the
    /// edited draft can preserve the engine plan for later evaluation/adaptation.
    public let enginePlanID: String?
    public let engineRevisionID: String?
    public let enginePlanJSON: Data?

    /// How many of the chosen movements came from the style's own pool. The
    /// chooser reports this, because a style narrows the movements without ever
    /// leaving a gap unaddressed on purpose (NFR-8).
    public var inStyleExerciseCount: Int { exercises.filter(\.isInStyle).count }

    public init(style: SuggestedWorkoutStyle, plan: WorkoutPlan,
                exercises: [SuggestedWorkoutExercise], initialDeficits: [String: Double],
                remainingDeficits: [String: Double], plannedSetTotal: Int,
                capTrimmingOccurred: Bool, citationIDs: [String],
                enginePlanID: String? = nil, engineRevisionID: String? = nil,
                enginePlanJSON: Data? = nil) {
        self.style = style
        self.plan = plan
        self.exercises = exercises
        self.initialDeficits = initialDeficits
        self.remainingDeficits = remainingDeficits
        self.plannedSetTotal = plannedSetTotal
        self.capTrimmingOccurred = capTrimmingOccurred
        self.citationIDs = citationIDs
        self.enginePlanID = enginePlanID
        self.engineRevisionID = engineRevisionID
        self.enginePlanJSON = enginePlanJSON
    }

    public var isLaunchable: Bool { !exercises.isEmpty }
    public var unresolvedDeficits: [String: Double] {
        remainingDeficits.filter { $0.value > SuggestedWorkoutGenerator.epsilon }
    }
}

public struct SuggestedWorkoutDiagnostics: Equatable, Sendable {
    public let rawCandidateCount: Int
    public let indexedCandidateCount: Int
    public let indexBuildCount: Int
    public let invertedListLookupCount: Int
    public let invertedCandidateVisitCount: Int
    public let fullCatalogScanCount: Int
    public let vectorIndexBuildDuration: Duration
    public let allStylesGenerationDuration: Duration

    public init(rawCandidateCount: Int, indexedCandidateCount: Int, indexBuildCount: Int,
                invertedListLookupCount: Int, invertedCandidateVisitCount: Int,
                fullCatalogScanCount: Int, vectorIndexBuildDuration: Duration,
                allStylesGenerationDuration: Duration) {
        self.rawCandidateCount = rawCandidateCount
        self.indexedCandidateCount = indexedCandidateCount
        self.indexBuildCount = indexBuildCount
        self.invertedListLookupCount = invertedListLookupCount
        self.invertedCandidateVisitCount = invertedCandidateVisitCount
        self.fullCatalogScanCount = fullCatalogScanCount
        self.vectorIndexBuildDuration = vectorIndexBuildDuration
        self.allStylesGenerationDuration = allStylesGenerationDuration
    }
}

public struct SuggestedWorkoutBundle: Equatable, Sendable {
    public let options: [SuggestedWorkoutOption]
    public let diagnostics: SuggestedWorkoutDiagnostics
    public let historyQuality: SuggestedWorkoutHistoryQuality
    public let personalizedHistoryWorkoutCount: Int

    public init(options: [SuggestedWorkoutOption], diagnostics: SuggestedWorkoutDiagnostics,
                historyQuality: SuggestedWorkoutHistoryQuality = .sufficient,
                personalizedHistoryWorkoutCount: Int = 0) {
        self.options = options
        self.diagnostics = diagnostics
        self.historyQuality = historyQuality
        self.personalizedHistoryWorkoutCount = max(0, personalizedHistoryWorkoutCount)
    }

    /// One option per style, in `SuggestedWorkoutStyle.allCases` order.
    public func option(_ style: SuggestedWorkoutStyle) -> SuggestedWorkoutOption {
        options.first { $0.style == style } ?? options[0]
    }
}

/// App state needed to ask DB++ for a suggested workout. Keeping this as a
/// value snapshot makes the generator safe to run off the main actor and keeps
/// SwiftData/UI types outside the engine boundary.
public struct SuggestedWorkoutEngineContext: Equatable, Sendable {
    public let experience: ExperienceLevel
    public let schedule: CoachSchedulePreferences
    public let availableEquipment: [Equipment]
    public let environment: String
    public let asOf: Date

    public init(experience: ExperienceLevel = .intermediate,
                schedule: CoachSchedulePreferences = .default,
                availableEquipment: [Equipment] = Equipment.allCases,
                environment: String = "commercial_gym",
                asOf: Date = Date()) {
        self.experience = experience
        self.schedule = schedule
        self.availableEquipment = availableEquipment
        self.environment = environment
        self.asOf = asOf
    }
}

public struct SuggestedWorkoutInput: Equatable, Sendable {
    public let completedSetsByMuscle: [String: Double]
    public let candidates: [SuggestedExerciseCandidate]
    /// Encoded finalized app history for DB++'s optional history-aware planning.
    /// The app owns extraction; the engine receives only this immutable snapshot.
    public let historyData: Data?
    public let historyWorkoutCount: Int
    public let historyWorkingSetCount: Int
    /// The muscle groups the plan targets. Deficits are computed over these only —
    /// otherwise the solver spends slots on groups the catalog cannot train
    /// (decision D4).
    public let trackedGroups: Set<MuscleGroup>
    public let preferredSetsPerExercise: Int
    public let trainingGoal: TrainingGoal
    /// The user's preferred workout family. It is a fallback for Personalized
    /// generation when history has no relevant movement, never a replacement for
    /// a relevant movement already found in history.
    public let preferredStyle: SuggestedWorkoutStyle
    public let engineContext: SuggestedWorkoutEngineContext?

    public init(completedSetsByMuscle: [String: Double],
                candidates: [SuggestedExerciseCandidate],
                historyData: Data? = nil,
                historyWorkoutCount: Int = 0,
                historyWorkingSetCount: Int = 0,
                trackedGroups: Set<MuscleGroup> = MuscleGroup.defaultTracked,
                preferredSetsPerExercise: Int,
                trainingGoal: TrainingGoal,
                preferredStyle: SuggestedWorkoutStyle = .fitness,
                engineContext: SuggestedWorkoutEngineContext? = nil) {
        self.completedSetsByMuscle = completedSetsByMuscle
        self.candidates = candidates
        self.historyData = historyData
        self.historyWorkoutCount = max(0, historyWorkoutCount)
        self.historyWorkingSetCount = max(0, historyWorkingSetCount)
        self.trackedGroups = trackedGroups.isEmpty ? MuscleGroup.defaultTracked : trackedGroups
        self.preferredSetsPerExercise = preferredSetsPerExercise
        self.trainingGoal = trainingGoal
        self.preferredStyle = preferredStyle == .personalized ? .fitness : preferredStyle
        self.engineContext = engineContext
    }

    /// A copy with one more candidate removed from the pool, by
    /// `SuggestedExerciseCandidate.id` (the same key
    /// `ExerciseSuggestionExclusionKey.forExercise`/`.forTemplate` produce).
    ///
    /// Exists so the app can regenerate a suggested workout in place the
    /// moment the user excludes one of its exercises — real user report:
    /// excluding an exercise from a suggested workout left it sitting right
    /// there in the plan, because the exclusion only ever affected *future*
    /// suggestion runs, never the one already on screen. `candidates` here
    /// already reflects whatever exclusions were active when the original
    /// suggestion was generated, so this only ever needs to remove the one
    /// newly-excluded id and hand the result straight back to
    /// `SuggestedWorkoutGenerator.generate` for a real from-scratch rerun —
    /// never a patch of the existing plan.
    public func excluding(candidateID: String) -> SuggestedWorkoutInput {
        SuggestedWorkoutInput(
            completedSetsByMuscle: completedSetsByMuscle,
            candidates: candidates.filter { $0.id != candidateID },
            historyData: historyData,
            historyWorkoutCount: historyWorkoutCount,
            historyWorkingSetCount: historyWorkingSetCount,
            trackedGroups: trackedGroups,
            preferredSetsPerExercise: preferredSetsPerExercise,
            trainingGoal: trainingGoal,
            preferredStyle: preferredStyle,
            engineContext: engineContext)
    }
}

public enum SuggestedWorkoutGenerator {
    public static let epsilon = 1e-9
    public static let minimumHistoryWorkouts = 3
    public static let minimumHistoryWorkingSets = 12
    public static let minimumPersonalizedWorkouts = 5

    public static func historyQuality(for input: SuggestedWorkoutInput) -> SuggestedWorkoutHistoryQuality {
        guard input.historyWorkoutCount > 0 || input.historyWorkingSetCount > 0 else {
            return .unavailable
        }
        guard input.historyWorkoutCount >= minimumHistoryWorkouts,
              input.historyWorkingSetCount >= minimumHistoryWorkingSets else {
            return .limited(workoutCount: input.historyWorkoutCount,
                            workingSetCount: input.historyWorkingSetCount)
        }
        return .sufficient
    }

    public static func generate(input: SuggestedWorkoutInput) -> SuggestedWorkoutBundle {
        let historyQuality = historyQuality(for: input)
        if let context = input.engineContext,
           let engineBundle = generateWithEngine(input: input, context: context) {
            return engineBundle
        }
        let clock = ContinuousClock()
        let indexStart = clock.now
        let index = SuggestedWorkoutVectorIndex(candidates: input.candidates,
                                                tracked: input.trackedGroups)
        let indexDuration = indexStart.duration(to: clock.now)
        let completed = index.muscleSpace.completedVector(input.completedSetsByMuscle)
        let preferredSets = min(4, max(3, input.preferredSetsPerExercise))

        var counters = Counters()
        let generationStart = clock.now
        // One index, six styles: every style solves the same 4-set-per-group
        // target and differs only in which movements it reaches for first.
        let options = SuggestedWorkoutStyle.allCases.map {
            solve(style: $0, completed: completed, preferredSets: preferredSets,
                  goal: input.trainingGoal, historyWorkoutCount: input.historyWorkoutCount,
                  index: index, counters: &counters)
        }
        let generationDuration = generationStart.duration(to: clock.now)

        return SuggestedWorkoutBundle(
            options: options,
            diagnostics: SuggestedWorkoutDiagnostics(
                rawCandidateCount: index.rawCandidateCount,
                indexedCandidateCount: index.exercises.count,
                indexBuildCount: 1,
                invertedListLookupCount: counters.lookups,
                invertedCandidateVisitCount: counters.visits,
                fullCatalogScanCount: 0,
                vectorIndexBuildDuration: indexDuration,
                allStylesGenerationDuration: generationDuration),
            historyQuality: historyQuality,
            personalizedHistoryWorkoutCount: input.historyWorkoutCount
        )
    }

    /// Generates the single user-facing Personalized workout. Unlike the old
    /// chooser API, this deliberately returns one option and remains launchable
    /// before five workouts: historical movements are preferred once available;
    /// the onboarding style fills only gaps (or supplies the initial pool).
    public static func generatePersonalized(input: SuggestedWorkoutInput) -> SuggestedWorkoutOption {
        let clock = ContinuousClock()
        let indexStart = clock.now
        let index = SuggestedWorkoutVectorIndex(candidates: input.candidates,
                                                tracked: input.trackedGroups)
        let indexDuration = indexStart.duration(to: clock.now)
        let completed = index.muscleSpace.completedVector(input.completedSetsByMuscle)
        let preferredSets = min(4, max(3, input.preferredSetsPerExercise))
        var counters = Counters()
        let generationStart = clock.now
        let option = solve(style: .personalized,
                           completed: completed,
                           preferredSets: preferredSets,
                           goal: input.trainingGoal,
                           historyWorkoutCount: input.historyWorkoutCount,
                           preferredStyle: input.preferredStyle,
                           allowPersonalizedFallback: true,
                           index: index,
                           counters: &counters)
        _ = SuggestedWorkoutDiagnostics(
            rawCandidateCount: index.rawCandidateCount,
            indexedCandidateCount: index.exercises.count,
            indexBuildCount: 1,
            invertedListLookupCount: counters.lookups,
            invertedCandidateVisitCount: counters.visits,
            fullCatalogScanCount: 0,
            vectorIndexBuildDuration: indexDuration,
            allStylesGenerationDuration: generationStart.duration(to: clock.now))
        return option
    }

    /// Chooses exactly one movement for an existing plan or live workout. The
    /// plan's own prescribed/completed work is added to the weekly vector before
    /// scoring, so this is the same gap solver as full suggestions rather than a
    /// generic random exercise picker.
    public static func suggestSingleExercise(
        input: SuggestedWorkoutInput,
        style: SuggestedWorkoutStyle,
        alreadyAllocatedByMuscle: [String: Double] = [:],
        excludingCandidateIDs: Set<String> = [],
        allowPersonalizedFallback: Bool = false
    ) -> SuggestedWorkoutExercise? {
        guard style != .personalized || allowPersonalizedFallback
            || input.historyWorkoutCount >= minimumPersonalizedWorkouts else {
            return nil
        }
        let index = SuggestedWorkoutVectorIndex(candidates: input.candidates,
                                                tracked: input.trackedGroups)
        let completed = index.muscleSpace.completedVector(input.completedSetsByMuscle)
        let allocated = index.muscleSpace.completedVector(alreadyAllocatedByMuscle)
        let target = Double(suggestedWorkoutTargetSetsPerGroup)
        let deficits = index.muscleSpace.muscleIDs.indices.map { dimension in
            max(0, target - completed[dimension] - allocated[dimension])
        }
        let preferredSets = min(4, max(3, input.preferredSetsPerExercise))
        let historyMembership = index.styleMembership[.personalized] ??
            Array(repeating: false, count: index.exercises.count)
        let biasMembership = index.styleMembership[input.preferredStyle] ??
            Array(repeating: true, count: index.exercises.count)
        let inStyle = style == .personalized
            ? (input.historyWorkoutCount >= minimumPersonalizedWorkouts
               ? historyMembership : biasMembership)
            : (index.styleMembership[style] ?? Array(repeating: true, count: index.exercises.count))

        func allowed(_ candidateIndex: Int, restrictedToStyle: Bool) -> Bool {
            guard !excludingCandidateIDs.contains(index.exercises[candidateIndex].candidate.id) else {
                return false
            }
            guard !restrictedToStyle || inStyle[candidateIndex] else { return false }
            let candidate = index.exercises[candidateIndex].candidate
            let policyStyle = style == .personalized ? input.preferredStyle : style
            if policyStyle != .olympic,
               candidate.trainingTypes.contains(.olympicWeightlifting)
                || ExerciseTrainingType.isOlympicOnlyMovement(named: candidate.name) {
                return false
            }
            return true
        }

        func bestCandidate(restrictedToStyle: Bool) -> Selection? {
            var best: Selection?
            for candidateIndex in index.exercises.indices where allowed(candidateIndex,
                                                                        restrictedToStyle: restrictedToStyle) {
                let exercise = index.exercises[candidateIndex]
                let candidateScore = score(exercise, deficits: deficits, preferredSets: preferredSets)
                guard candidateScore.total > epsilon else { continue }
                let selection = Selection(candidateIndex: candidateIndex,
                                          score: candidateScore,
                                          isInStyle: inStyle[candidateIndex])
                if best == nil || isBetter(selection, than: best!, index: index) {
                    best = selection
                }
            }
            return best
        }

        if let best = bestCandidate(restrictedToStyle: true) ??
            (style == .personalized && input.historyWorkoutCount >= minimumPersonalizedWorkouts
             ? bestCandidateForMembership(biasMembership) : nil) ??
            (style != .bodyweight ? bestCandidate(restrictedToStyle: false) : nil) {
            let exercise = index.exercises[best.candidateIndex]
            return outputExercise(exercise, preferredSets: preferredSets,
                                  repRange: input.trainingGoal.repRange,
                                  score: best.score.total,
                                  isInStyle: best.isInStyle,
                                  muscleSpace: index.muscleSpace)
        }

        // A fully covered workout can still need one useful add-on. Keep the
        // style boundary and omit every movement already in the workout.
        let maintenancePool = index.exercises.indices.filter {
            allowed($0, restrictedToStyle: true)
        }
        let fallbackPool = style == .bodyweight ? [] : index.exercises.indices.filter {
            allowed($0, restrictedToStyle: false) && !inStyle[$0]
        }
        let maintenance = (maintenancePool + fallbackPool).sorted { lhs, rhs in
            let left = index.exercises[lhs]
            let right = index.exercises[rhs]
            if left.candidate.mechanics != right.candidate.mechanics {
                return left.candidate.mechanics == .compound
            }
            if left.elements.count != right.elements.count {
                return left.elements.count > right.elements.count
            }
            let nameOrder = left.candidate.name.localizedCaseInsensitiveCompare(right.candidate.name)
            return nameOrder == .orderedAscending ||
                (nameOrder == .orderedSame && left.candidate.id < right.candidate.id)
        }.first
        guard let maintenance else { return nil }
        return outputExercise(index.exercises[maintenance], preferredSets: preferredSets,
                              repRange: input.trainingGoal.repRange,
                              score: 0, isInStyle: inStyle[maintenance],
                              muscleSpace: index.muscleSpace)

        func bestCandidateForMembership(_ membership: [Bool]) -> Selection? {
            var best: Selection?
            for candidateIndex in index.exercises.indices where membership[candidateIndex] {
                guard !excludingCandidateIDs.contains(index.exercises[candidateIndex].candidate.id) else { continue }
                let candidate = index.exercises[candidateIndex].candidate
                let policyStyle = style == .personalized ? input.preferredStyle : style
                if policyStyle != .olympic && (candidate.trainingTypes.contains(.olympicWeightlifting)
                    || ExerciseTrainingType.isOlympicOnlyMovement(named: candidate.name)) { continue }
                let candidateScore = score(index.exercises[candidateIndex], deficits: deficits,
                                           preferredSets: preferredSets)
                guard candidateScore.total > epsilon else { continue }
                let selection = Selection(candidateIndex: candidateIndex, score: candidateScore,
                                          isInStyle: membership[candidateIndex])
                if best == nil || isBetter(selection, than: best!, index: index) { best = selection }
            }
            return best
        }
    }

    private static func generateWithEngine(
        input: SuggestedWorkoutInput,
        context: SuggestedWorkoutEngineContext
    ) -> SuggestedWorkoutBundle? {
        let generationStart = ContinuousClock.now
        let styles = SuggestedWorkoutStyle.allCases
        // Keep the engine call for one canonical Fitness plan and use the
        // already-indexed app solver for the remaining style projections. The
        // old implementation generated Fitness once and relabeled that plan
        // six ways, which made Bodyweight show Clean and Jerk. Six independent
        // engine passes would fix that but make the chooser unnecessarily slow
        // on a full catalog. The app solver has the explicit style facets and
        // remains deterministic, fast, and editable.
        let index = SuggestedWorkoutVectorIndex(candidates: input.candidates,
                                                tracked: input.trackedGroups)
        let completed = index.muscleSpace.completedVector(input.completedSetsByMuscle)
        let preferredSets = min(4, max(3, input.preferredSetsPerExercise))
        var counters = Counters()
        var options = styles.map {
            solve(style: $0, completed: completed, preferredSets: preferredSets,
                  goal: input.trainingGoal, historyWorkoutCount: input.historyWorkoutCount,
                  index: index, counters: &counters)
        }
        let olympicCandidateIDs = Set(input.candidates
            .filter { $0.trainingTypes.contains(.olympicWeightlifting)
                || ExerciseTrainingType.isOlympicOnlyMovement(named: $0.name) }
            .map(\.id))
        let olympicCandidateNames = Set(input.candidates
            .filter { $0.trainingTypes.contains(.olympicWeightlifting)
                || ExerciseTrainingType.isOlympicOnlyMovement(named: $0.name) }
            .map { $0.name.localizedLowercase })
        if let engineOption = TrainingEngineBridge.suggestedWorkout(
            input: input,
            context: context,
            style: .fitness)?.option,
           let fitnessIndex = styles.firstIndex(of: .fitness),
           engineOption.isLaunchable,
           engineOption.exercises.allSatisfy({ exercise in
               !olympicCandidateIDs.contains(exercise.candidateID)
                   && !olympicCandidateNames.contains(exercise.name.localizedLowercase)
           }) {
            options[fitnessIndex] = engineOption
        }
        guard options.filter({ $0.style != .personalized }).allSatisfy(\.isLaunchable) else { return nil }
        let duration = generationStart.duration(to: ContinuousClock.now)
        let diagnostics = SuggestedWorkoutDiagnostics(
            rawCandidateCount: input.candidates.count,
            indexedCandidateCount: index.exercises.count,
            indexBuildCount: 1,
            invertedListLookupCount: counters.lookups,
            invertedCandidateVisitCount: counters.visits,
            fullCatalogScanCount: 0,
            vectorIndexBuildDuration: .zero,
            allStylesGenerationDuration: duration)
        return SuggestedWorkoutBundle(
            options: options,
            diagnostics: diagnostics,
            historyQuality: historyQuality(for: input),
            personalizedHistoryWorkoutCount: input.historyWorkoutCount)
    }

    private struct Counters {
        var lookups = 0
        var visits = 0
    }

    private struct Score {
        let total: Double
    }

    private struct Selection {
        let candidateIndex: Int
        let score: Score
        let isInStyle: Bool
    }

    /// Solves one style.
    ///
    /// Two passes, because no sport pool can cover the ontology — Olympic
    /// weightlifting reaches six of twenty muscle groups directly. Pass one fills
    /// the plan from the style's own movements; pass two continues over everything
    /// else for styles that allow general-strength borrowing. Bodyweight is an
    /// explicit equipment boundary and never borrows an external-load movement.
    private static func solve(style: SuggestedWorkoutStyle, completed: [Double],
                              preferredSets: Int, goal: TrainingGoal,
                              historyWorkoutCount: Int,
                              preferredStyle: SuggestedWorkoutStyle = .fitness,
                              allowPersonalizedFallback: Bool = false,
                              index: SuggestedWorkoutVectorIndex,
                              counters: inout Counters) -> SuggestedWorkoutOption {
        let target = Double(suggestedWorkoutTargetSetsPerGroup)
        let initial = index.muscleSpace.deficits(target: target, completed: completed)
        var deficits = initial
        var selected = Array(repeating: false, count: index.exercises.count)
        var choices: [SuggestedWorkoutExercise] = []
        let historyMembership = index.styleMembership[.personalized] ??
            Array(repeating: false, count: index.exercises.count)
        let biasMembership = index.styleMembership[preferredStyle] ??
            Array(repeating: true, count: index.exercises.count)
        let inStyle = style == .personalized && allowPersonalizedFallback
            ? (historyWorkoutCount >= minimumPersonalizedWorkouts ? historyMembership : biasMembership)
            : (index.styleMembership[style] ?? Array(repeating: true, count: index.exercises.count))

        if style == .personalized && historyWorkoutCount < minimumPersonalizedWorkouts && !allowPersonalizedFallback {
            return emptyOption(style: style, goal: goal, initial: initial,
                               muscleSpace: index.muscleSpace)
        }

        func fill(restrictedToStyle: Bool, membership: [Bool], outputMembership: [Bool]) {
            var generations = Array(repeating: 0, count: deficits.count)
            var activeMask = UInt32(0)
            var heap = SuggestedWorkoutDeficitHeap()
            for dimension in deficits.indices where deficits[dimension] > epsilon {
                activeMask |= UInt32(1) << UInt32(dimension)
                heap.push(.init(deficit: deficits[dimension], dimension: dimension,
                                massPriority: index.muscleSpace.massPriority(of: dimension), generation: 0))
            }

            while let entry = heap.pop() {
                guard entry.generation == generations[entry.dimension],
                      deficits[entry.dimension] > epsilon,
                      abs(entry.deficit - deficits[entry.dimension]) <= epsilon else { continue }

                counters.lookups += 1
                var best: Selection?
                for candidateIndex in index.inverted[entry.dimension] where !selected[candidateIndex] {
                    if restrictedToStyle && !membership[candidateIndex] { continue }
                    counters.visits += 1
                    let exercise = index.exercises[candidateIndex]
                    let policyStyle = style == .personalized ? preferredStyle : style
                    if policyStyle != .olympic,
                       (exercise.candidate.trainingTypes.contains(.olympicWeightlifting)
                        || ExerciseTrainingType.isOlympicOnlyMovement(named: exercise.candidate.name)) {
                        continue
                    }
                    guard exercise.coverageMask & activeMask != 0 else { continue }
                    let score = score(exercise, deficits: deficits, preferredSets: preferredSets)
                    guard score.total > epsilon else { continue }
                    let selection = Selection(candidateIndex: candidateIndex, score: score,
                                              isInStyle: inStyle[candidateIndex])
                    if best == nil || isBetter(selection, than: best!, index: index) {
                        best = selection
                    }
                }

                guard let best else {
                    generations[entry.dimension] += 1
                    activeMask &= ~(UInt32(1) << UInt32(entry.dimension))
                    continue
                }

                selected[best.candidateIndex] = true
                let exercise = index.exercises[best.candidateIndex]
                choices.append(outputExercise(exercise, preferredSets: preferredSets,
                                              repRange: goal.repRange, score: best.score.total,
                                              isInStyle: outputMembership[best.candidateIndex],
                                              muscleSpace: index.muscleSpace))
                for element in exercise.elements where deficits[element.dimension] > epsilon {
                    deficits[element.dimension] = max(
                        0,
                        deficits[element.dimension] - Double(preferredSets) * element.weight
                    )
                    generations[element.dimension] += 1
                    if deficits[element.dimension] > epsilon {
                        heap.push(.init(deficit: deficits[element.dimension],
                                        dimension: element.dimension,
                                        massPriority: index.muscleSpace.massPriority(of: element.dimension),
                                        generation: generations[element.dimension]))
                    } else {
                        activeMask &= ~(UInt32(1) << UInt32(element.dimension))
                    }
                }
            }
        }

        fill(restrictedToStyle: true, membership: inStyle, outputMembership: inStyle)
        if style == .personalized && allowPersonalizedFallback,
           historyWorkoutCount >= minimumPersonalizedWorkouts {
            // Keep history-first ordering, then use the onboarding bias only for
            // muscle gaps history could not cover.
            fill(restrictedToStyle: true, membership: biasMembership,
                 outputMembership: biasMembership)
        }
        if style != .personalized && (style != .bodyweight || !inStyle.contains(true)) {
            fill(restrictedToStyle: false, membership: inStyle, outputMembership: inStyle)
        }

        // A suggestion is an on-demand workout, not only a gap-filling alert.
        // Once this week's tracked gaps are already covered, the old solver
        // returned an empty option and the UI incorrectly reported that the
        // exercise catalog was unavailable. Keep the same style preference and
        // offer one maintenance movement so users with substantial history can
        // still review and edit a workout.
        if choices.isEmpty,
           let maintenance = maintenanceSelection(style: style, index: index,
                                                   inStyle: inStyle) {
            let exercise = index.exercises[maintenance]
            choices.append(outputExercise(
                exercise, preferredSets: preferredSets, repRange: goal.repRange,
                score: 0, isInStyle: inStyle[maintenance],
                muscleSpace: index.muscleSpace))
        }

        let untrimmedCount = choices.count
        while choices.count * preferredSets > suggestedWorkoutPlannedSetCap {
            choices.removeLast()
        }
        let remaining = recomputeDeficits(initial: initial, exercises: choices,
                                          muscleSpace: index.muscleSpace)
        let plan = WorkoutPlan(
            id: "coach-suggested-\(style.rawValue)",
            name: style.planName,
            source: .coachSuggested,
            scheme: .strength,
            items: choices.enumerated().map {
                PlanItem(id: $0.offset, movement: $0.element.name,
                         reps: goal.repRange.lowerBound,
                         targetSets: $0.element.plannedSets)
            }
        )
        return SuggestedWorkoutOption(
            style: style,
            plan: plan,
            exercises: choices,
            initialDeficits: index.muscleSpace.dictionary(initial),
            remainingDeficits: index.muscleSpace.dictionary(remaining),
            plannedSetTotal: choices.count * preferredSets,
            capTrimmingOccurred: choices.count != untrimmedCount,
            citationIDs: suggestedWorkoutCitationIDs
        )
    }

    private static func emptyOption(style: SuggestedWorkoutStyle, goal: TrainingGoal,
                                    initial: [Double],
                                    muscleSpace: SuggestedWorkoutMuscleSpace) -> SuggestedWorkoutOption {
        let plan = WorkoutPlan(id: "coach-suggested-\(style.rawValue)",
                               name: style.planName, source: .coachSuggested,
                               scheme: .strength, items: [])
        return SuggestedWorkoutOption(
            style: style, plan: plan, exercises: [],
            initialDeficits: muscleSpace.dictionary(initial),
            remainingDeficits: muscleSpace.dictionary(initial),
            plannedSetTotal: 0, capTrimmingOccurred: false,
            citationIDs: suggestedWorkoutCitationIDs)
    }

    /// Deterministically chooses a style movement for a maintenance suggestion.
    /// If a style has no catalog member, the general catalog fallback preserves
    /// the same disclosure used by gap-filling suggestions.
    private static func maintenanceSelection(
        style: SuggestedWorkoutStyle,
        index: SuggestedWorkoutVectorIndex,
        inStyle: [Bool]
    ) -> Int? {
        let preferred = index.exercises.indices.filter { inStyle[$0] }
        let fallback = index.exercises.indices.filter {
            !inStyle[$0]
                && (style == .olympic
                    || (!index.exercises[$0].candidate.trainingTypes.contains(.olympicWeightlifting)
                        && !ExerciseTrainingType.isOlympicOnlyMovement(
                            named: index.exercises[$0].candidate.name)))
        }
        let pool = style == .personalized ? preferred : preferred + fallback
        return pool.sorted { lhs, rhs in
            let left = index.exercises[lhs]
            let right = index.exercises[rhs]
            if left.candidate.mechanics != right.candidate.mechanics {
                return left.candidate.mechanics == .compound
            }
            if left.elements.count != right.elements.count {
                return left.elements.count > right.elements.count
            }
            let nameOrder = left.candidate.name.localizedCaseInsensitiveCompare(right.candidate.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return left.candidate.id < right.candidate.id
        }.first
    }

    private static func score(_ exercise: SuggestedWorkoutIndexedExercise,
                              deficits: [Double], preferredSets: Int) -> Score {
        var total = 0.0
        for element in exercise.elements where deficits[element.dimension] > epsilon {
            let credit = min(deficits[element.dimension], Double(preferredSets) * element.weight)
            total += credit
        }
        return Score(total: total)
    }

    private static func isBetter(_ lhs: Selection, than rhs: Selection,
                                 index: SuggestedWorkoutVectorIndex) -> Bool {
        if abs(lhs.score.total - rhs.score.total) > epsilon {
            return lhs.score.total > rhs.score.total
        }
        // Only reachable in the fallback pass, where an out-of-style movement can
        // tie one the style pass skipped for another reason.
        if lhs.isInStyle != rhs.isInStyle { return lhs.isInStyle }
        let left = index.exercises[lhs.candidateIndex].candidate
        let right = index.exercises[rhs.candidateIndex].candidate
        if left.mechanics != right.mechanics { return left.mechanics == .compound }
        let leftCoverage = index.exercises[lhs.candidateIndex].elements.count
        let rightCoverage = index.exercises[rhs.candidateIndex].elements.count
        if leftCoverage != rightCoverage { return leftCoverage > rightCoverage }
        let nameOrder = left.name.localizedCaseInsensitiveCompare(right.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return left.id < right.id
    }

    private static func outputExercise(_ exercise: SuggestedWorkoutIndexedExercise,
                                       preferredSets: Int, repRange: ClosedRange<Int>,
                                       score: Double, isInStyle: Bool,
                                       muscleSpace: SuggestedWorkoutMuscleSpace) -> SuggestedWorkoutExercise {
        SuggestedWorkoutExercise(
            candidateID: exercise.candidate.id,
            name: exercise.candidate.name,
            mechanics: exercise.candidate.mechanics,
            plannedSets: preferredSets,
            repRange: repRange,
            contributions: exercise.elements.map {
                SuggestedMuscleContribution(
                    muscleID: muscleSpace.muscleIDs[$0.dimension],
                    weight: $0.weight,
                    plannedSetContribution: Double(preferredSets) * $0.weight
                )
            },
            selectionScore: score,
            isInStyle: isInStyle
        )
    }

    private static func recomputeDeficits(initial: [Double],
                                          exercises: [SuggestedWorkoutExercise],
                                          muscleSpace: SuggestedWorkoutMuscleSpace) -> [Double] {
        var result = initial
        for exercise in exercises {
            for contribution in exercise.contributions {
                guard let dimension = muscleSpace.dimensionByID[contribution.muscleID] else { continue }
                result[dimension] = max(0, result[dimension] - contribution.plannedSetContribution)
            }
        }
        return result
    }
}
