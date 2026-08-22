import Foundation

public let suggestedWorkoutCitationIDs = [
    "iversenTimeEfficient2021",
    "pellandFractionalSets2024",
]

public struct SuggestedExerciseCandidate: Equatable, Sendable {
    public let id: String
    public let name: String
    public let mechanics: Mechanics
    public let primaryMuscles: [String]
    public let secondaryMuscles: [String]

    public init(id: String, name: String, mechanics: Mechanics,
                primaryMuscles: [String], secondaryMuscles: [String] = []) {
        self.id = id
        self.name = name
        self.mechanics = mechanics
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
    }
}

public enum SuggestedWorkoutTier: String, CaseIterable, Equatable, Sendable {
    case minimum, medium, maximal

    public var targetSetsPerMuscle: Int {
        switch self {
        case .minimum: 4
        case .medium: 8
        case .maximal: 12
        }
    }

    public var plannedSetCap: Int {
        switch self {
        case .minimum: 20
        case .medium: 30
        case .maximal: 40
        }
    }

    public var planName: String {
        switch self {
        case .minimum: "Minimum Plan"
        case .medium: "Medium Plan"
        case .maximal: "Maximal Plan"
        }
    }
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

    public init(candidateID: String, name: String, mechanics: Mechanics, plannedSets: Int,
                repRange: ClosedRange<Int>, contributions: [SuggestedMuscleContribution],
                selectionScore: Double) {
        self.candidateID = candidateID
        self.name = name
        self.mechanics = mechanics
        self.plannedSets = plannedSets
        self.repRange = repRange
        self.contributions = contributions
        self.selectionScore = selectionScore
    }
}

public struct SuggestedWorkoutOption: Equatable, Sendable {
    public let tier: SuggestedWorkoutTier
    public let plan: WorkoutPlan
    public let exercises: [SuggestedWorkoutExercise]
    public let initialDeficits: [String: Double]
    public let remainingDeficits: [String: Double]
    public let plannedSetTotal: Int
    public let capTrimmingOccurred: Bool
    public let citationIDs: [String]

    public init(tier: SuggestedWorkoutTier, plan: WorkoutPlan,
                exercises: [SuggestedWorkoutExercise], initialDeficits: [String: Double],
                remainingDeficits: [String: Double], plannedSetTotal: Int,
                capTrimmingOccurred: Bool, citationIDs: [String]) {
        self.tier = tier
        self.plan = plan
        self.exercises = exercises
        self.initialDeficits = initialDeficits
        self.remainingDeficits = remainingDeficits
        self.plannedSetTotal = plannedSetTotal
        self.capTrimmingOccurred = capTrimmingOccurred
        self.citationIDs = citationIDs
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
    public let threeTierGenerationDuration: Duration

    public init(rawCandidateCount: Int, indexedCandidateCount: Int, indexBuildCount: Int,
                invertedListLookupCount: Int, invertedCandidateVisitCount: Int,
                fullCatalogScanCount: Int, vectorIndexBuildDuration: Duration,
                threeTierGenerationDuration: Duration) {
        self.rawCandidateCount = rawCandidateCount
        self.indexedCandidateCount = indexedCandidateCount
        self.indexBuildCount = indexBuildCount
        self.invertedListLookupCount = invertedListLookupCount
        self.invertedCandidateVisitCount = invertedCandidateVisitCount
        self.fullCatalogScanCount = fullCatalogScanCount
        self.vectorIndexBuildDuration = vectorIndexBuildDuration
        self.threeTierGenerationDuration = threeTierGenerationDuration
    }
}

public struct SuggestedWorkoutBundle: Equatable, Sendable {
    public let options: [SuggestedWorkoutOption]
    public let diagnostics: SuggestedWorkoutDiagnostics

    public init(options: [SuggestedWorkoutOption], diagnostics: SuggestedWorkoutDiagnostics) {
        self.options = options
        self.diagnostics = diagnostics
    }

    public var minimum: SuggestedWorkoutOption { options[0] }
    public var medium: SuggestedWorkoutOption { options[1] }
    public var maximal: SuggestedWorkoutOption { options[2] }
}

public struct SuggestedWorkoutInput: Equatable, Sendable {
    public let completedSetsByMuscle: [String: Double]
    public let candidates: [SuggestedExerciseCandidate]
    public let preferredSetsPerExercise: Int
    public let trainingGoal: TrainingGoal

    public init(completedSetsByMuscle: [String: Double],
                candidates: [SuggestedExerciseCandidate],
                preferredSetsPerExercise: Int,
                trainingGoal: TrainingGoal) {
        self.completedSetsByMuscle = completedSetsByMuscle
        self.candidates = candidates
        self.preferredSetsPerExercise = preferredSetsPerExercise
        self.trainingGoal = trainingGoal
    }
}

public enum SuggestedWorkoutGenerator {
    public static let epsilon = 1e-9

    public static func generate(input: SuggestedWorkoutInput) -> SuggestedWorkoutBundle {
        let clock = ContinuousClock()
        let indexStart = clock.now
        let index = SuggestedWorkoutVectorIndex(candidates: input.candidates)
        let indexDuration = indexStart.duration(to: clock.now)
        let completed = index.muscleSpace.completedVector(input.completedSetsByMuscle)
        let preferredSets = min(4, max(3, input.preferredSetsPerExercise))

        var counters = Counters()
        let generationStart = clock.now
        let options = SuggestedWorkoutTier.allCases.map {
            solve(tier: $0, completed: completed, preferredSets: preferredSets,
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
                threeTierGenerationDuration: generationDuration
            )
        )
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
    }

    private static func solve(tier: SuggestedWorkoutTier, completed: [Double],
                              preferredSets: Int, goal: TrainingGoal,
                              index: SuggestedWorkoutVectorIndex,
                              counters: inout Counters) -> SuggestedWorkoutOption {
        let target = Double(tier.targetSetsPerMuscle)
        let initial = index.muscleSpace.deficits(target: target, completed: completed)
        var deficits = initial
        var generations = Array(repeating: 0, count: deficits.count)
        var activeMask = UInt32(0)
        var heap = SuggestedWorkoutDeficitHeap()
        for dimension in deficits.indices where deficits[dimension] > epsilon {
            activeMask |= UInt32(1) << UInt32(dimension)
            heap.push(.init(deficit: deficits[dimension], dimension: dimension,
                            massPriority: index.muscleSpace.massPriority(of: dimension), generation: 0))
        }

        var selected = Array(repeating: false, count: index.exercises.count)
        var choices: [SuggestedWorkoutExercise] = []
        while let entry = heap.pop() {
            guard entry.generation == generations[entry.dimension],
                  deficits[entry.dimension] > epsilon,
                  abs(entry.deficit - deficits[entry.dimension]) <= epsilon else { continue }

            counters.lookups += 1
            var best: Selection?
            for candidateIndex in index.inverted[entry.dimension] where !selected[candidateIndex] {
                counters.visits += 1
                let exercise = index.exercises[candidateIndex]
                guard exercise.coverageMask & activeMask != 0 else { continue }
                let score = score(exercise, deficits: deficits, preferredSets: preferredSets)
                guard score.total > epsilon else { continue }
                let selection = Selection(candidateIndex: candidateIndex, score: score)
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

        let untrimmedCount = choices.count
        while choices.count * preferredSets > tier.plannedSetCap {
            choices.removeLast()
        }
        let remaining = recomputeDeficits(initial: initial, exercises: choices,
                                          muscleSpace: index.muscleSpace)
        let plan = WorkoutPlan(
            id: "coach-suggested-\(tier.rawValue)",
            name: tier.planName,
            source: .coachSuggested,
            scheme: .strength,
            items: choices.enumerated().map {
                PlanItem(id: $0.offset, movement: $0.element.name,
                         reps: goal.repRange.lowerBound,
                         targetSets: $0.element.plannedSets)
            }
        )
        return SuggestedWorkoutOption(
            tier: tier,
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
                                       score: Double,
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
            selectionScore: score
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
