import Foundation
import CadenceCore

/// Phase E (field-test-fixes): swap/remove exercise in a workout session.
public enum ExerciseSwap {

    public enum SwapTarget: Identifiable {
        case planned(name: String)
        case logged(exerciseID: UUID)

        public var id: String {
            switch self {
            case .planned(let name): return "planned.\(name)"
            case .logged(let id): return "logged.\(id.uuidString)"
            }
        }
    }
}
