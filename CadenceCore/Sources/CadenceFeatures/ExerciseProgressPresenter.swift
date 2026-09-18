import Foundation
import CadenceCore

/// Pure summary calculation for the exercise-level progress drill-down.
/// Keeping this outside SwiftUI makes the latest/best/session contract cheap to
/// test and prevents the view from growing another history query.
public enum ExerciseProgressPresenter {
    public struct Summary: Equatable, Sendable {
        public let latest: WorkoutRepository.TrendPoint?
        public let best: Double?
        public let sessionCount: Int

        public init(latest: WorkoutRepository.TrendPoint?, best: Double?, sessionCount: Int) {
            self.latest = latest
            self.best = best
            self.sessionCount = sessionCount
        }
    }

    public static func summary(points: [WorkoutRepository.TrendPoint]) -> Summary {
        let latest = points.max { $0.date < $1.date }
        return Summary(latest: latest,
                       best: points.map(\.value).max(),
                       sessionCount: points.count)
    }
}
