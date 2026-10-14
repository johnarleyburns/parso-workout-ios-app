import Foundation

public struct WeekCloseMoment: Equatable, Sendable {
    public let title: String
    public let detail: String

    public static func make(workingSets: Double, setTarget: Double,
                            cardioMinutes: Double, cardioTarget: Double) -> WeekCloseMoment? {
        let complete = [workingSets >= setTarget, cardioMinutes >= cardioTarget].allSatisfy { $0 }
        guard complete, setTarget > 0, cardioTarget > 0 else { return nil }
        return WeekCloseMoment(title: String(localized: "Week complete", bundle: .module),
                               detail: String(localized: "You reached your strength set and cardio minute goals.", bundle: .module))
    }
}
