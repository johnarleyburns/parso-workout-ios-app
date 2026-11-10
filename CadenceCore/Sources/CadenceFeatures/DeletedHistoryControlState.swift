import Foundation
import CadenceCore

/// Top-bar "Show Deleted" / "Back to Workouts" control for My Workouts.
public struct DeletedHistoryControlState: Equatable, Sendable {
    public let isVisible: Bool
    public let title: String
    public let nextVisibility: HistoryVisibility

    public static func make(visibility: HistoryVisibility, deletedCount: Int) -> DeletedHistoryControlState? {
        guard deletedCount > 0 else { return nil }
        switch visibility {
        case .active: return .init(isVisible: true, title: "Show Deleted", nextVisibility: .deleted)
        case .deleted: return .init(isVisible: true, title: "Back to Workouts", nextVisibility: .active)
        }
    }
}
