import Foundation

public struct WeekCloseMoment: Equatable, Sendable {
    public let title: String
    public let detail: String

    public static func make(workingSets: Double, setTarget: Double,
                            cardioMinutes: Double, cardioTarget: Double,
                            sessions: Double, sessionTarget: Double) -> WeekCloseMoment? {
        let complete = [workingSets >= setTarget, cardioMinutes >= cardioTarget,
                        sessions >= sessionTarget].allSatisfy { $0 }
        guard complete, setTarget > 0, cardioTarget > 0, sessionTarget > 0 else { return nil }
        return WeekCloseMoment(title: "Week complete",
                               detail: "You reached your strength, cardio, and consistency goals.")
    }
}
