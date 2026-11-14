import Foundation

/// Foundation-only presentation/selection rules for the Watch More sheet's "Set details".
public enum WatchRPESelection {
    /// Selectable integer RPE values (None is represented by `nil`).
    public static let options: [Int] = Array(1...10)

    public static func rowText(mode: WatchEffortMode, value: Double?) -> String {
        guard let value else { return "—" }
        return "\(mode.displayName) \(Int(value.rounded()))"
    }

    /// Applies a picker choice; always normalizes to RPE mode. `nil` clears the effort.
    public static func apply(_ choice: Int?, mode: inout WatchEffortMode, value: inout Double?) {
        mode = .rpe
        value = choice.map { Double($0) }
    }

    /// Coach guidance appears in More only when a plan line exists.
    public static func coachGuidance(from line: WatchCoachLine?) -> WatchCoachLine? { line }
}
