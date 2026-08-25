import Foundation

/// DB++-driven similarity for exercise substitution. The value type keeps the
/// ranker identical on iPhone, watch, and in headless tests.
public enum ExerciseSimilarity {
    public struct Prepared: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let direct: Set<MuscleGroup>
        public let indirect: Set<MuscleGroup>
        public let patterns: Set<String>
        public let mechanics: Mechanics?
        public let force: Force?
        public let equipment: Equipment?
        public let modalities: Set<ExerciseModality>
        public let trainingTypes: Set<ExerciseTrainingType>
        public let volumeEligible: Bool

        public init(id: String = UUID().uuidString, name: String, direct: Set<MuscleGroup>, indirect: Set<MuscleGroup>, patterns: Set<String> = [], mechanics: Mechanics? = nil, force: Force? = nil, equipment: Equipment? = nil, modalities: Set<ExerciseModality> = [], trainingTypes: Set<ExerciseTrainingType> = [], volumeEligible: Bool = true) {
            self.id = id; self.name = name; self.direct = direct; self.indirect = indirect
            self.patterns = patterns; self.mechanics = mechanics; self.force = force
            self.equipment = equipment; self.modalities = modalities; self.trainingTypes = trainingTypes
            self.volumeEligible = volumeEligible
        }
    }

    public struct Result: Equatable, Sendable, Identifiable {
        public let candidate: Prepared
        public let score: Double
        public let directOverlap: Double
        public let indirectOverlap: Double
        public let borrowed: Bool
        public var id: String { candidate.id }
    }

    public static func score(source: Prepared, candidate: Prepared) -> Result? {
        guard source.id != candidate.id, source.name != candidate.name else { return nil }
        let direct = jaccard(source.direct, candidate.direct)
        let indirect = jaccard(source.indirect, candidate.indirect)
        let pattern = source.patterns.isDisjoint(with: candidate.patterns) ? 0 : 1
        let mechanics = source.mechanics == candidate.mechanics && source.mechanics != nil ? 0.05 : 0
        let force = source.force == candidate.force && source.force != nil ? 0.05 : 0
        let equipment: Double = source.equipment == candidate.equipment && source.equipment != nil ? 1 : (source.modalities.intersection(candidate.modalities).isEmpty ? 0 : 0.5)
        let total = direct * 0.45 + indirect * 0.20 + Double(pattern) * 0.20 + mechanics + force + equipment * 0.05
        return Result(candidate: candidate, score: total, directOverlap: direct, indirectOverlap: indirect, borrowed: false)
    }

    public static func rank(source: Prepared, candidates: [Prepared], selectedType: ExerciseTrainingType? = nil, limit: Int = 12) -> [Result] {
        let scored = candidates.compactMap { score(source: source, candidate: $0) }
        let preferred = scored.filter { result in selectedType.map { type in result.candidate.trainingTypes.contains(type) } ?? true }
        let preferredIDs = Set(preferred.map(\.id))
        let sortedPreferred = preferred.sorted { order($0, $1) }
        let borrowed = scored.filter { !preferredIDs.contains($0.id) }.sorted { order($0, $1) }.map {
            Result(candidate: $0.candidate, score: $0.score, directOverlap: $0.directOverlap, indirectOverlap: $0.indirectOverlap, borrowed: true)
        }
        return Array((sortedPreferred + borrowed).prefix(limit))
    }

    public static func availableTypes(source: Prepared, candidates: [Prepared]) -> [ExerciseTrainingType] {
        ExerciseTrainingType.allCases.filter { type in
            !rank(source: source, candidates: candidates, selectedType: type, limit: 1).isEmpty
                && candidates.contains { $0.trainingTypes.contains(type) }
        }
    }

    private static func jaccard(_ lhs: Set<MuscleGroup>, _ rhs: Set<MuscleGroup>) -> Double {
        guard !lhs.isEmpty || !rhs.isEmpty else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(lhs.union(rhs).count)
    }

    private static func order(_ lhs: Result, _ rhs: Result) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.candidate.volumeEligible != rhs.candidate.volumeEligible { return lhs.candidate.volumeEligible }
        let li = lhs.candidate.direct.first.flatMap { MuscleGroup.canonicalOrder.firstIndex(of: $0) } ?? Int.max
        let ri = rhs.candidate.direct.first.flatMap { MuscleGroup.canonicalOrder.firstIndex(of: $0) } ?? Int.max
        return li == ri ? lhs.candidate.name < rhs.candidate.name : li < ri
    }
}
