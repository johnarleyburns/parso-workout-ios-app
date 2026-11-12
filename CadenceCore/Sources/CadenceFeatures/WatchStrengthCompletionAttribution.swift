import Foundation
import CadenceCore

/// One result binding the Watch strength summary's HR data and the weekly overlay contribution to
/// the exact same finalized samples and profile. All minute math is the phone's
/// `CardioMinuteAccumulator` (via `WatchStrengthHRCoverage.summary`); nothing is duplicated here.
public struct WatchStrengthCompletionAttribution: Equatable, Sendable {
    public let hrSamples: [HRSamplePoint]
    public let cardioSummary: CardioMinuteSummary?
    public let overlay: WatchWeekLocalOverlay
    public var showsHeartRate: Bool { !hrSamples.isEmpty }

    public static func make(
        samples: [HRSamplePoint], duration: TimeInterval, profile: CardioIntensityProfile,
        ownerWorkingSetCount: Int, completionID: UUID, completedAt: Date,
        weekKey: (Date) -> String
    ) -> WatchStrengthCompletionAttribution {
        let summary = WatchStrengthHRCoverage.summary(samples: samples, duration: duration, profile: profile)
        return WatchStrengthCompletionAttribution(
            hrSamples: samples, cardioSummary: summary,
            overlay: WatchWeekLocalOverlay(
                id: completionID, weekKey: weekKey(completedAt), kind: .strength,
                sets: Double(ownerWorkingSetCount),
                moderateEquivalentMinutes: summary?.moderateEquivalentMinutes ?? 0,
                completedAt: completedAt))
    }
}

/// The single completion path shared by cooldown expiry, Skip, zero-cooldown direct summary and
/// inactivity finalization. Idempotent per completion ID (overlay store replaces by ID).
public enum WatchStrengthCompletionCoordinator {
    /// Records finalized HR on the model, builds the payload (minting the stable completion ID),
    /// records the overlay BEFORE transfer, then hands the payload to `send`.
    @MainActor
    @discardableResult
    public static func complete(
        model: WatchStrengthFlowModel, samples: [HRSamplePoint], profile: CardioIntensityProfile,
        outbox: WatchStrengthCompletionOutbox, weekKey: (Date) -> String,
        recordOverlay: (WatchWeekLocalOverlay) -> Void,
        send: ([String: Any]) -> Void
    ) -> WatchStrengthCompletionAttribution? {
        model.recordHeartRate(samples)
        guard let payload = model.endSessionPayload(completionOutbox: outbox) else { return nil }
        let attribution = attribution(model: model, profile: profile, weekKey: weekKey)
        if let attribution { recordOverlay(attribution.overlay) }
        send(payload)
        return attribution
    }

    /// Presentation for the model's finalized capture (nil until a completion ID exists).
    @MainActor
    public static func attribution(model: WatchStrengthFlowModel, profile: CardioIntensityProfile,
                                   weekKey: (Date) -> String) -> WatchStrengthCompletionAttribution? {
        guard let session = model.session,
              let id = session.completionID.flatMap(UUID.init(uuidString:)) else { return nil }
        return .make(samples: model.recordedHeartRate, duration: model.durationSeconds, profile: profile,
                     ownerWorkingSetCount: session.completedOwnerWorkingSetCount, completionID: id,
                     completedAt: session.endedAt ?? Date(), weekKey: weekKey)
    }
}
