import Foundation

public enum WatchHRLivePromotion {
    /// Returns only the newest observation that belongs to the active capture
    /// and is still physiologically fresh. Call only after durable persistence.
    public static func newestFreshObservation(
        in message: WatchHRMessage,
        activeSessionID: UUID?,
        activeRequestID: UUID?,
        now: Date,
        staleAfter: TimeInterval = WatchHRRelay.staleAfter
    ) -> WatchHRObservation? {
        guard message.kind == .observations,
              message.phoneWorkoutSessionID == activeSessionID,
              message.watchRequestID == activeRequestID,
              let newest = message.observations.max(by: { $0.sampleEnd < $1.sampleEnd })
        else { return nil }

        let observedAt = Date(timeIntervalSince1970: newest.sampleEnd)
        guard now.timeIntervalSince(observedAt) <= staleAfter else { return nil }
        return newest
    }
}
