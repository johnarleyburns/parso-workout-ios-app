import Foundation

/// One row on the Watch "My Workouts" page.
public struct WatchMyWorkoutRow: Equatable, Sendable, Identifiable {
    public enum Status: Sendable, Equatable { case planned, completed }
    public let id: String
    public let status: Status
    public let title: String
    /// Completed rows only; planned rows are today's plan.
    public let date: Date?
    /// Exercise names (planned) or logged working-set count (completed) summarised by the view.
    public let exerciseNames: [String]
    public let setCount: Int
    public let isCardio: Bool
}

/// Builds the Watch "My Workouts" list: today's planned sessions first, then recent history.
public enum WatchMyWorkouts {
    public struct HistoryInput: Sendable {
        public let id: UUID
        public let title: String
        public let date: Date
        public let setCount: Int
        public init(id: UUID, title: String, date: Date, setCount: Int) {
            self.id = id; self.title = title; self.date = date; self.setCount = setCount
        }
    }

    public static func rows(plan: WatchSync.TodayPlan?, history: [HistoryInput],
                            historyLimit: Int = 20) -> [WatchMyWorkoutRow] {
        let planned = (plan?.sessions ?? []).filter { $0.kind != .rest }.map {
            WatchMyWorkoutRow(id: "planned-\($0.id)", status: .planned,
                              title: $0.label.isEmpty ? ($0.kind == .strength ? "Strength" : "Cardio") : $0.label,
                              date: nil, exerciseNames: $0.exerciseNames, setCount: 0,
                              isCardio: $0.kind == .cardio)
        }
        let done = history.sorted { $0.date > $1.date }.prefix(max(0, historyLimit)).map {
            WatchMyWorkoutRow(id: "done-\($0.id.uuidString)", status: .completed,
                              title: $0.title.isEmpty ? "Workout" : $0.title,
                              date: $0.date, exerciseNames: [], setCount: $0.setCount, isCardio: false)
        }
        return planned + done
    }
}
