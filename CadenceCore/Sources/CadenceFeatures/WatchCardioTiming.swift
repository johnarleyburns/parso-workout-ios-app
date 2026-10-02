import Foundation

/// Resolves the wall-clock span of a cardio workout completed on Apple Watch.
///
/// The Watch runs a single `HKWorkoutSession`, and a phone-started strength
/// workout opens that same session only to relay live heart rate. The session's
/// shared start therefore can belong to a different workout. A cardio completion
/// must be timed from the cardio session's own start; only when that is missing
/// is the start reconstructed from the measured duration. Borrowing the shared
/// strength start makes an 8-minute HIIT report as the strength span plus the
/// HIIT span.
public struct WatchCardioTiming: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public init(cardioSessionStart: Date?, measuredDuration: TimeInterval, endedAt: Date) {
        self.end = endedAt
        if let cardioSessionStart {
            self.start = cardioSessionStart
        } else {
            self.start = endedAt.addingTimeInterval(-max(0, measuredDuration))
        }
    }
}
