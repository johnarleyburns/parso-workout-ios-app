import Foundation
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

    /// Records (or idempotently re-records) a Watch strength completion's
    /// contribution immediately, before the completion transfers to the phone,
    /// so a disconnected or retrying state shows the same total.
    func recordStrengthCompletionOverlay(completionID: UUID, ownerWorkingSetCount: Int, endedAt: Date) {
        weekOverlayStore.record(WatchWeekLocalOverlay(
            id: completionID,
            weekKey: Self.currentWeekKey(now: endedAt),
            kind: .strength,
            sets: Double(ownerWorkingSetCount),
            completedAt: endedAt))
        refreshWeekLocalOverlays()
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
