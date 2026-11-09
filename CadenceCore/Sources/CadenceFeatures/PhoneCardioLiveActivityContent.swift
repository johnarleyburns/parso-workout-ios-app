import Foundation
import CadenceCore

/// Pure projection of a live phone cardio session into Lock Screen / Dynamic Island
/// fields. ActivityKit is not headlessly testable, so the app maps this struct onto
/// `WorkoutLiveActivityAttributes.ContentState`.
public struct PhoneCardioLiveActivityContent: Equatable, Sendable {
    public var title: String
    public var symbol: String
    public var elapsedSeconds: Int
    public var isPaused: Bool
    /// Counted GPS distance; nil for indoor/swim sessions (no distance evidence).
    public var distanceMeters: Double?

    public init(session: PhoneLiveCardioSession, now: Date) {
        title = session.type.displayName
        symbol = session.type.symbol
        elapsedSeconds = Int(session.activeDuration(endedAt: now))
        isPaused = session.isPaused
        distanceMeters = session.lastCountedDistance > 0 ? session.lastCountedDistance : nil
    }

    /// True while the Live Activity should exist (a session that has not reached its terminal receipt).
    public static func isLive(_ session: PhoneLiveCardioSession?) -> Bool {
        guard let session else { return false }
        return session.receipt == nil
    }
}
