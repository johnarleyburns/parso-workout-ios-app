import Foundation
import CadenceCore

/// The sole constructor of a phone-published `WatchSync.WeekSummary` from
/// `HomeDashboardState`. Every place that publishes the Watch's weekly
/// baseline (cold launch, coach refresh, activity/cardio refresh, and the
/// live volume-change path) must route through this projection so the
/// Watch never sees a different weekly total than iPhone This Week.
public enum WatchWeekSummaryPresenter {
    public static func make(
        dashboard: HomeDashboardState,
        updatedAt: Date = Date()
    ) -> WatchSync.WeekSummary {
        let setsTarget = dashboard.volume
            .filter(\.isTracked)
            .reduce(0.0) { total, _ in total + 12 }

        return WatchSync.WeekSummary(
            sets: dashboard.volume.reduce(0.0) { $0 + $1.sets },
            setsMinimum: setsTarget / WeeklySetProgress.maximum * WeeklySetProgress.minimum,
            setsTarget: setsTarget,
            cardioMinutes: dashboard.cardioDetail.moderateEquivalentMinutes,
            updatedAt: updatedAt
        )
    }
}
