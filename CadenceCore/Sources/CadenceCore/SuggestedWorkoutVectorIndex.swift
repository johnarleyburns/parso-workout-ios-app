import Foundation

struct SuggestedWorkoutMuscleSpace: Sendable {
    let muscleIDs: [String]
    let dimensionByID: [String: Int]

    init() {
        muscleIDs = MuscleCatalog.all.map(\.id)
        dimensionByID = Dictionary(
            uniqueKeysWithValues: muscleIDs.enumerated().map { ($0.element, $0.offset) }
        )
    }

    func normalizedMuscleID(_ value: String) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty, dimensionByID[normalized] != nil else { return nil }
        return normalized
    }

    func completedVector(_ completed: [String: Double]) -> [Double] {
        var result = Array(repeating: 0.0, count: muscleIDs.count)
        for (muscleID, sets) in completed {
            guard sets.isFinite,
                  let normalized = normalizedMuscleID(muscleID),
                  let dimension = dimensionByID[normalized] else { continue }
            result[dimension] += sets
        }
        return result
    }

    func deficits(target: Double, completed: [Double]) -> [Double] {
        muscleIDs.indices.map { max(0, target - completed[$0]) }
    }

    func dictionary(_ values: [Double]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: muscleIDs.indices.map { (muscleIDs[$0], values[$0]) })
    }

    func massPriority(of dimension: Int) -> Int {
        MuscleCatalog.massPriority(for: muscleIDs[dimension])
    }
}

struct SuggestedWorkoutIndexedExercise: Sendable {
    struct Element: Sendable {
        let dimension: Int
        let weight: Double
    }

    let candidate: SuggestedExerciseCandidate
    let elements: [Element]
    let coverageMask: UInt32
}

struct SuggestedWorkoutVectorIndex: Sendable {
    let muscleSpace: SuggestedWorkoutMuscleSpace
    let exercises: [SuggestedWorkoutIndexedExercise]
    let inverted: [[Int]]
    let rawCandidateCount: Int

    init(candidates: [SuggestedExerciseCandidate]) {
        let space = SuggestedWorkoutMuscleSpace()
        muscleSpace = space
        rawCandidateCount = candidates.count

        struct CandidateGroup {
            var identity: SuggestedExerciseCandidate
            var primaryMuscles: [String]
            var secondaryMuscles: [String]
        }

        var groups: [String: CandidateGroup] = [:]
        for candidate in candidates {
            let trimmedName = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            let key = trimmedName.lowercased()
            let normalizedCandidate = SuggestedExerciseCandidate(
                id: candidate.id,
                name: trimmedName,
                mechanics: candidate.mechanics,
                primaryMuscles: candidate.primaryMuscles,
                secondaryMuscles: candidate.secondaryMuscles
            )
            if var group = groups[key] {
                if normalizedCandidate.id < group.identity.id {
                    group.identity = normalizedCandidate
                }
                group.primaryMuscles.append(contentsOf: candidate.primaryMuscles)
                group.secondaryMuscles.append(contentsOf: candidate.secondaryMuscles)
                groups[key] = group
            } else {
                groups[key] = CandidateGroup(
                    identity: normalizedCandidate,
                    primaryMuscles: candidate.primaryMuscles,
                    secondaryMuscles: candidate.secondaryMuscles
                )
            }
        }

        let orderedGroups = groups.sorted {
            if $0.key != $1.key { return $0.key < $1.key }
            return $0.value.identity.id < $1.value.identity.id
        }.map(\.value)

        var built: [SuggestedWorkoutIndexedExercise] = []
        for group in orderedGroups {
            let primary = Set(group.primaryMuscles.compactMap(space.normalizedMuscleID))
            let secondary = Set(group.secondaryMuscles.compactMap(space.normalizedMuscleID))
                .subtracting(primary)
            var elements: [SuggestedWorkoutIndexedExercise.Element] = []
            for dimension in space.muscleIDs.indices {
                let muscleID = space.muscleIDs[dimension]
                if primary.contains(muscleID) {
                    elements.append(.init(dimension: dimension, weight: 1.0))
                } else if secondary.contains(muscleID) {
                    elements.append(.init(dimension: dimension, weight: 0.5))
                }
            }
            guard !elements.isEmpty else { continue }
            let mask = elements.reduce(UInt32(0)) { $0 | (UInt32(1) << UInt32($1.dimension)) }
            built.append(.init(candidate: group.identity, elements: elements, coverageMask: mask))
        }
        exercises = built

        var lists = Array(repeating: [Int](), count: space.muscleIDs.count)
        for (candidateIndex, exercise) in built.enumerated() {
            for element in exercise.elements {
                lists[element.dimension].append(candidateIndex)
            }
        }
        inverted = lists
    }
}

struct SuggestedWorkoutDeficitHeap {
    struct Entry {
        let deficit: Double
        let dimension: Int
        let massPriority: Int
        let generation: Int
    }

    private var storage: [Entry] = []

    mutating func push(_ entry: Entry) {
        storage.append(entry)
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard Self.precedes(storage[child], storage[parent]) else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Entry? {
        guard !storage.isEmpty else { return nil }
        if storage.count == 1 { return storage.removeLast() }
        let result = storage[0]
        storage[0] = storage.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            guard left < storage.count else { break }
            let right = left + 1
            let child = right < storage.count && Self.precedes(storage[right], storage[left])
                ? right : left
            guard Self.precedes(storage[child], storage[parent]) else { break }
            storage.swapAt(child, parent)
            parent = child
        }
        return result
    }

    private static func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.deficit != rhs.deficit { return lhs.deficit > rhs.deficit }
        if lhs.massPriority != rhs.massPriority { return lhs.massPriority < rhs.massPriority }
        if lhs.dimension != rhs.dimension { return lhs.dimension < rhs.dimension }
        return lhs.generation > rhs.generation
    }
}
