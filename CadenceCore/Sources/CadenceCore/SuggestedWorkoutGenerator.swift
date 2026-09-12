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
    /// False for stretching, plyometrics and cardio: such a movement can never be
    /// suggested as strength work, whatever muscles it lists (decision D3).
    public let volumeEligible: Bool
    public let trainingTypes: [ExerciseTrainingType]
    public let modalities: [ExerciseModality]
    public let sportContexts: [ExerciseSportContext]

    public init(id: String, name: String, mechanics: Mechanics,
                primaryMuscles: [String], secondaryMuscles: [String] = [],
                volumeEligible: Bool = true,
                trainingTypes: [ExerciseTrainingType] = [.strength],
                modalities: [ExerciseModality] = [],
                sportContexts: [ExerciseSportContext] = [.generalFitness]) {
        self.id = id
        self.name = name
        self.mechanics = mechanics
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.volumeEligible = volumeEligible
        self.trainingTypes = trainingTypes
        self.modalities = modalities
        self.sportContexts = sportContexts
    }

    /// Builds the value sent to the suggestion engine from the canonical
    /// in-memory catalog. The app uses this as a safe fallback while an existing
    /// SwiftData store is still seeding or when an older store has unusable
    /// exercise facets.
    public init(template: ExerciseTemplate) {
        self.init(id: template.sourceExerciseID ?? template.id,
                  name: template.name,
                  mechanics: template.mechanics,
                  primaryMuscles: template.primaryMuscles,
                  secondaryMuscles: template.secondaryMuscles,
                  volumeEligible: template.volumeEligible,
                  trainingTypes: template.trainingTypes,
                  modalities: template.modalities,
                  sportContexts: template.sportContexts)
    }

    /// Whether this movement belongs to a training style's own pool.
    public func matches(_ style: SuggestedWorkoutStyle) -> Bool {
        switch style {
        case .fitness:
            return trainingTypes.contains(.strength) && sportContexts == [.generalFitness]
        case .bodyweight:
            return modalities.contains(.bodyweight)
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
    case fitness, bodyweight, powerlifting, olympic, strongman

    public var displayName: String {
        switch self {
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

    public init(options: [SuggestedWorkoutOption], diagnostics: SuggestedWorkoutDiagnostics) {
        self.options = options
        self.diagnostics = diagnostics
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
    /// The muscle groups the plan targets. Deficits are computed over these only —
    /// otherwise the solver spends slots on groups the catalog cannot train
    /// (decision D4).
    public let trackedGroups: Set<MuscleGroup>
    public let preferredSetsPerExercise: Int
    public let trainingGoal: TrainingGoal
    public let engineContext: SuggestedWorkoutEngineContext?

    public init(completedSetsByMuscle: [String: Double],
                candidates: [SuggestedExerciseCandidate],
                trackedGroups: Set<MuscleGroup> = MuscleGroup.defaultTracked,
                preferredSetsPerExercise: Int,
                trainingGoal: TrainingGoal,
                engineContext: SuggestedWorkoutEngineContext? = nil) {
        self.completedSetsByMuscle = completedSetsByMuscle
        self.candidates = candidates
        self.trackedGroups = trackedGroups.isEmpty ? MuscleGroup.defaultTracked : trackedGroups
        self.preferredSetsPerExercise = preferredSetsPerExercise
        self.trainingGoal = trainingGoal
        self.engineContext = engineContext
    }
}

public enum SuggestedWorkoutGenerator {
    public static let epsilon = 1e-9

    public static func generate(input: SuggestedWorkoutInput) -> SuggestedWorkoutBundle {
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
        // One index, five styles: every style solves the same 4-set-per-group
        // target and differs only in which movements it reaches for first.
        let options = SuggestedWorkoutStyle.allCases.map {
            solve(style: $0, completed: completed, preferredSets: preferredSets,
                  goal: input.trainingGoal, index: index, counters: &counters)
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
                allStylesGenerationDuration: generationDuration
            )
        )
    }

    private static func generateWithEngine(
        input: SuggestedWorkoutInput,
        context: SuggestedWorkoutEngineContext
    ) -> SuggestedWorkoutBundle? {
        let generationStart = ContinuousClock.now
        let styles = SuggestedWorkoutStyle.allCases
        // One chooser request should have one canonical engine plan. The style
        // buttons are soft presentation biases over that plan; projecting them
        // here avoids five independent planner/evaluator passes on device while
        // preserving each option's style membership and engine provenance.
        guard let base = TrainingEngineBridge.suggestedWorkout(
            input: input,
            context: context,
            style: .fitness) else { return nil }
        let options = styles.map { restyle(base.option, as: $0) }
        let duration = generationStart.duration(to: ContinuousClock.now)
        let diagnostics = SuggestedWorkoutDiagnostics(
            rawCandidateCount: input.candidates.count,
            indexedCandidateCount: TrainingEngineBridge.exerciseRecords.count,
            indexBuildCount: 1,
            invertedListLookupCount: 0,
            invertedCandidateVisitCount: 0,
            fullCatalogScanCount: 0,
            vectorIndexBuildDuration: .zero,
            allStylesGenerationDuration: duration)
        return SuggestedWorkoutBundle(
            options: options,
            diagnostics: diagnostics)
    }

    private struct Counters {
        var lookups = 0
        var visits = 0
    }

    private static func restyle(
        _ option: SuggestedWorkoutOption,
        as style: SuggestedWorkoutStyle
    ) -> SuggestedWorkoutOption {
        guard style != option.style else { return option }
        let styleIDs = Set(TrainingEngineBridge.preferredExerciseIDs(for: style))
        let exercises = option.exercises.map { exercise in
            SuggestedWorkoutExercise(
                candidateID: exercise.candidateID,
                name: exercise.name,
                mechanics: exercise.mechanics,
                plannedSets: exercise.plannedSets,
                repRange: exercise.repRange,
                contributions: exercise.contributions,
                selectionScore: exercise.selectionScore,
                isInStyle: styleIDs.contains(exercise.candidateID))
        }
        let plan = WorkoutPlan(
            id: "coach-suggested-\(style.rawValue)",
            name: style.planName,
            source: option.plan.source,
            scheme: option.plan.scheme,
            items: option.plan.items,
            notes: option.plan.notes)
        return SuggestedWorkoutOption(
            style: style,
            plan: plan,
            exercises: exercises,
            initialDeficits: option.initialDeficits,
            remainingDeficits: option.remainingDeficits,
            plannedSetTotal: option.plannedSetTotal,
            capTrimmingOccurred: option.capTrimmingOccurred,
            citationIDs: option.citationIDs,
            enginePlanID: option.enginePlanID,
            engineRevisionID: option.engineRevisionID,
            enginePlanJSON: option.enginePlanJSON)
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
    /// else, but only for gaps the style could not close. A style therefore
    /// narrows the movements without ever leaving a gap unaddressed on purpose
    /// (NFR-8: the coach suggests, it does not proscribe).
    private static func solve(style: SuggestedWorkoutStyle, completed: [Double],
                              preferredSets: Int, goal: TrainingGoal,
                              index: SuggestedWorkoutVectorIndex,
                              counters: inout Counters) -> SuggestedWorkoutOption {
        let target = Double(suggestedWorkoutTargetSetsPerGroup)
        let initial = index.muscleSpace.deficits(target: target, completed: completed)
        var deficits = initial
        var selected = Array(repeating: false, count: index.exercises.count)
        var choices: [SuggestedWorkoutExercise] = []
        let inStyle = index.styleMembership[style] ?? Array(repeating: true, count: index.exercises.count)

        func fill(restrictedToStyle: Bool) {
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
                    if restrictedToStyle && !inStyle[candidateIndex] { continue }
                    counters.visits += 1
                    let exercise = index.exercises[candidateIndex]
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
                                              isInStyle: best.isInStyle,
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

        fill(restrictedToStyle: true)
        fill(restrictedToStyle: false)

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
