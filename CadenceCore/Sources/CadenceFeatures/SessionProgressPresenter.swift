import Foundation

public struct SessionProgress: Equatable, Sendable {
    public let completed: Int
    public let planned: Int
    public var label: String { String(localized: "\(completed) of \(planned) sets", bundle: .module) }
    public init(completed: Int, planned: Int) {
        self.completed = max(0, completed); self.planned = max(self.completed, planned)
    }
}

public enum SessionProgressPresenter {
    public static func progress(completedWorkingSets: Int, plannedWorkingSets: Int) -> SessionProgress {
        SessionProgress(completed: completedWorkingSets, planned: plannedWorkingSets)
    }
}
