import Foundation

public struct PRMoment: Equatable, Sendable {
    public let headline: String
    public let context: String
    public let performerName: String?
    public init(headline: String, context: String, performerName: String? = nil) {
        self.headline = headline; self.context = context; self.performerName = performerName
    }
}

public enum PRMomentPresenter {
    public static func moment(exercise: String, loadText: String, changeText: String,
                              isNewPR: Bool, isWarmup: Bool, isPartnerSet: Bool,
                              performerName: String? = nil) -> PRMoment? {
        guard isNewPR, !isWarmup else { return nil }
        let headline = isPartnerSet ? "\(performerName ?? "Partner")'s new personal record" : "New personal record"
        return PRMoment(headline: headline, context: "\(exercise) \(loadText) · \(changeText)",
                        performerName: performerName)
    }
}
