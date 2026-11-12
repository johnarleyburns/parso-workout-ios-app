import Foundation
import WatchConnectivity
import CadenceCore
import CadenceFeatures

/// The Watch-local completion overlay (issue: Watch This Week renders zero
/// while disconnected, then must reconcile with the phone baseline without a
/// zero flash or double count). The phone (`WatchWeekSummaryPresenter`)
/// remains the sole weekly-total authority; this overlay only adds a
/// completion the phone has not yet acknowledged, and only for the current
/// week.
extension WatchWorkoutManager {
    static func currentWeekKey(now: Date = Date()) -> String { AppSettings.weekKey(for: now) }

    /// Reloads the current week's unresolved overlays from the durable store and
    /// prunes anything outside the current/previous week so the store cannot
    /// grow unbounded across relaunches.
    func refreshWeekLocalOverlays(now: Date = Date()) {
        let currentKey = Self.currentWeekKey(now: now)
        let previousKey = Self.currentWeekKey(now: now.addingTimeInterval(-7 * 24 * 3600))
        weekOverlayStore.prune(keepingWeekKeys: [currentKey, previousKey])
        weekLocalOverlays = weekOverlayStore.overlays(forWeekKey: currentKey)
    }

    /// Records (or idempotently re-records) a Watch strength completion's contribution
    /// (sets + moderate-equivalent minutes from the shared attribution) before transfer.
    /// Same ID replaces; never duplicates.
    func recordStrengthCompletionOverlay(_ contribution: WatchWeekLocalOverlay) {
        weekOverlayStore.record(contribution)
        refreshWeekLocalOverlays()
    }

    /// The single Watch strength end path: finalize HR first (callers must not have stopped the
    /// workout), record the overlay, then send the existing completion payload.
    @discardableResult
    func completeStrengthWorkout(model: WatchStrengthFlowModel, capture: [HRSamplePoint]? = nil, endReason: StrengthEndReason? = nil) -> WatchStrengthCompletionAttribution? {
        let profile = watchAppSettings?.resolvedCardioIntensityProfile
            ?? CardioIntensityProfile.resolved(userEnteredMaximumHR: nil, age: nil)
        let samples = capture ?? finalizeStrengthHRCapture().samples
        return WatchStrengthCompletionCoordinator.complete(
            model: model, samples: samples, profile: profile, outbox: strengthCompletionOutbox,
            weekKey: { Self.currentWeekKey(now: $0) },
            recordOverlay: { recordStrengthCompletionOverlay($0) },
            send: { payload in
                var payload = payload
                if let reason = endReason { payload["end_reason"] = reason.rawValue }
                guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
                WCSession.default.transferUserInfo(payload)
                strengthCompletionOutbox.flush()
            })
    }

    /// Records a Watch cardio completion's moderate-equivalent minute credit,
    /// derived with the same `CardioMinuteAccumulator` policy the phone uses so
    /// the overlay and the eventual phone-imported total agree. Zero HR/intensity
    /// credit records as zero, never as raw duration.
    func recordCardioCompletionOverlay(_ completion: WatchCardioCompletion) {
        let profile = watchAppSettings?.resolvedCardioIntensityProfile
            ?? CardioIntensityProfile.resolved(userEnteredMaximumHR: nil, age: nil)
        let minutes = CardioMinuteAccumulator.summarize(
            duration: completion.end.timeIntervalSince(completion.start),
            samples: completion.hrSamples,
            profile: profile
        ).moderateEquivalentMinutes
        weekOverlayStore.record(WatchWeekLocalOverlay(
            id: completion.id,
            weekKey: Self.currentWeekKey(now: completion.end),
            kind: .cardio,
            moderateEquivalentMinutes: minutes,
            completedAt: completion.end))
        refreshWeekLocalOverlays()
    }

    /// The phone has absorbed this completion into its baseline; remove it so a
    /// later baseline sync is additive-free (never double counted).
    func acknowledgeWeekOverlay(id: UUID) {
        weekOverlayStore.acknowledge(id: id)
        refreshWeekLocalOverlays()
    }
}
