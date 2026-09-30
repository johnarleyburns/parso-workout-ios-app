import Foundation

public enum RestAlarmAction: Equatable, Sendable {
    case schedule(Date)
    case cancel
    case none
}
/// Pure rest-alert state machine. AlarmKit is deliberately kept in the app
/// target; this type defines the cancellation rules shared by phone and Watch.
public struct RestAlarmPlanner: Sendable {
    public private(set) var endsAt: Date?
    public private(set) var watchOwnsCue = false

    public init() {}

    public mutating func start(endsAt: Date, watchOwnsCue: Bool = false) -> RestAlarmAction {
        self.endsAt = endsAt
        self.watchOwnsCue = watchOwnsCue
        return watchOwnsCue ? .cancel : .schedule(endsAt)
    }

    public mutating func extend(to newEnd: Date) -> RestAlarmAction {
        endsAt = newEnd
        return watchOwnsCue ? .cancel : .schedule(newEnd)
    }

    public mutating func skip() -> RestAlarmAction {
        endsAt = nil
        return .cancel
    }

    public mutating func logSet() -> RestAlarmAction {
        endsAt = nil
        return .cancel
    }

    public mutating func endWorkout() -> RestAlarmAction {
        endsAt = nil
        return .cancel
    }
}
