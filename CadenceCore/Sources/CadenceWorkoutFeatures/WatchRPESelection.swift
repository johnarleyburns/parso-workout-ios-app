import CadenceFeatures
import Foundation

/// Foundation-only presentation/selection rules for the Watch RPE picker.
public enum WatchRPESelection {
    /// Selectable integer RPE values (None is represented by `nil`).
    public static let options: [Int] = Array(1...10)

    /// Applies a picker choice; always normalizes to RPE mode. `nil` clears the effort.
    public static func apply(_ choice: Int?, mode: inout WatchEffortMode, value: inout Double?) {
        mode = .rpe
        value = choice.map { Double($0) }
    }
}
