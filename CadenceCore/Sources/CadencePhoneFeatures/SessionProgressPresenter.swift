import CadenceFeatures
import Foundation

public struct SessionProgress: Equatable, Sendable {
    public let completed: Int
    public let planned: Int
    public var label: String { {
        #if os(Linux)
        "\(completed) of \(planned) sets"
        #else
        String(localized: "\(completed) of \(planned) sets", bundle: FeatureLocalization.bundle)
        #endif
    }() }
    public init(completed: Int, planned: Int) {
        self.completed = max(0, completed); self.planned = max(self.completed, planned)
    }
}

public enum SessionProgressPresenter {
    public static func progress(completedWorkingSets: Int, plannedWorkingSets: Int) -> SessionProgress {
        SessionProgress(completed: completedWorkingSets, planned: plannedWorkingSets)
    }
}
