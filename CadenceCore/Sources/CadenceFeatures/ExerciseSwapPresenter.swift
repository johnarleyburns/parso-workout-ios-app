import Foundation
import CadenceCore

public struct ExerciseSwapPresenter: Sendable {
    public let source: ExerciseSimilarity.Prepared
    public let candidates: [ExerciseSimilarity.Prepared]
    public let availableTypes: [ExerciseTrainingType]

    public init(source: ExerciseSimilarity.Prepared, candidates: [ExerciseSimilarity.Prepared]) {
        self.source = source
        self.candidates = candidates.filter { $0.id != source.id && $0.name != source.name }
        self.availableTypes = ExerciseSimilarity.availableTypes(source: source, candidates: self.candidates)
    }

    public var defaultType: ExerciseTrainingType { source.trainingTypes.first ?? .strength }

    public func results(for type: ExerciseTrainingType) -> [ExerciseSimilarity.Result] {
        ExerciseSimilarity.rank(source: source, candidates: candidates, selectedType: type)
    }
}
