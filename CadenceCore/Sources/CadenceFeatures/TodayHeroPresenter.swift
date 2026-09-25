import Foundation

public struct TodayHero: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case suggested, scheduled, inProgress, restDay, needsHistory }
    public struct Line: Equatable, Sendable {
        public let name: String
        public let detail: String
        public init(name: String, detail: String) { self.name = name; self.detail = detail }
    }
    public let kind: Kind
    public let title: String
    public let estimatedMinutes: Int?
    public let exercises: [Line]
    public let reason: String?
    public let citationIDs: [String]
    public let computedAt: Date

    public init(kind: Kind, title: String, estimatedMinutes: Int? = nil,
                exercises: [Line] = [], reason: String? = nil,
                citationIDs: [String] = [], computedAt: Date = Date()) {
        self.kind = kind; self.title = title; self.estimatedMinutes = estimatedMinutes
        self.exercises = Array(exercises.prefix(5)); self.reason = reason
        self.citationIDs = citationIDs; self.computedAt = computedAt
    }
}

public enum TodayHeroPresenter {
    public static func hero(inProgress: TodayHero?, scheduled: TodayHero?, suggested: TodayHero?,
                            completedWorkoutCount: Int, computedAt: Date = Date()) -> TodayHero {
        if let inProgress { return inProgress.with(kind: .inProgress, computedAt: computedAt) }
        if let scheduled { return scheduled.with(kind: .scheduled, computedAt: computedAt) }
        if completedWorkoutCount < 2 {
            return TodayHero(kind: .needsHistory,
                             title: "Log a workout and your coach will start suggesting.",
                             computedAt: computedAt)
        }
        return (suggested ?? TodayHero(kind: .restDay, title: "Recovery day", computedAt: computedAt))
            .with(computedAt: computedAt)
    }
}

private extension TodayHero {
    func with(kind: Kind? = nil, computedAt: Date) -> TodayHero {
        TodayHero(kind: kind ?? self.kind, title: title, estimatedMinutes: estimatedMinutes,
                  exercises: exercises, reason: reason, citationIDs: citationIDs, computedAt: computedAt)
    }
}
