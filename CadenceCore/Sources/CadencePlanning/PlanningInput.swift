import Foundation

/// Why a `PlanningInput` was rejected.
public enum PlanningInputError: Error, Sendable, Equatable {
    case strengthDaysOutOfRange(Int)
    case cardioDaysOutOfRange(Int)
    case invalidRollingRest(Int)
    case invalidWeekday(Int)
    case tooManySessions(requested: Int, available: Int)
}

/// Validated, Foundation-only scheduling inputs. Behavior mirrors the app's
/// existing ranges (strength 2…5, cardio 0…7) without removing those fields.
public struct PlanningInput: Sendable, Equatable {
    public static let strengthDaysRange = 2...5
    public static let cardioDaysRange = 0...7

    public let strengthDaysPerWeek: Int
    public let cardioDaysPerWeek: Int
    public let restRule: PlanningRestRule
    public let policy: PlanningPolicy

    public init(strengthDaysPerWeek: Int, cardioDaysPerWeek: Int,
                restRule: PlanningRestRule, policy: PlanningPolicy = .safe) throws {
        guard Self.strengthDaysRange.contains(strengthDaysPerWeek) else {
            throw PlanningInputError.strengthDaysOutOfRange(strengthDaysPerWeek)
        }
        guard Self.cardioDaysRange.contains(cardioDaysPerWeek) else {
            throw PlanningInputError.cardioDaysOutOfRange(cardioDaysPerWeek)
        }
        switch restRule {
        case .rolling(let n):
            guard n >= 1 else { throw PlanningInputError.invalidRollingRest(n) }
        case .fixed(let days):
            if let bad = days.first(where: { !(1...7).contains($0) }) {
                throw PlanningInputError.invalidWeekday(bad)
            }
        }
        self.strengthDaysPerWeek = strengthDaysPerWeek
        self.cardioDaysPerWeek = cardioDaysPerWeek
        self.restRule = restRule
        self.policy = policy
    }
}

public enum PlanningSessionKind: String, Sendable, Equatable {
    case strength, cardio, rest
}

/// One day's slot in the planned week (day 0 = week start).
public struct PlanningDaySlot: Sendable, Equatable {
    public let dayIndex: Int
    public let weekday: Int
    public let kinds: [PlanningSessionKind]
}

public struct PlanningOutput: Sendable, Equatable {
    public let slots: [PlanningDaySlot]
    public var strengthCount: Int { slots.filter { $0.kinds.contains(.strength) }.count }
    public var cardioCount: Int { slots.filter { $0.kinds.contains(.cardio) }.count }
}

/// Deterministic day-slot placement: same input → same output, no clock,
/// randomness, or locale.
public enum WeekSlotPlanner {
    /// - Parameter weekStartWeekday: Gregorian weekday (1…7) of day 0.
    public static func plan(_ input: PlanningInput, weekStartWeekday: Int) throws -> PlanningOutput {
        guard (1...7).contains(weekStartWeekday) else {
            throw PlanningInputError.invalidWeekday(weekStartWeekday)
        }
        let days = (0..<7).map { (index: $0, weekday: (weekStartWeekday - 1 + $0) % 7 + 1) }
        let open = days.filter {
            !PlanningRestRule.isRestDay(weekday: $0.weekday, daysSinceWeekStart: $0.index, rule: input.restRule)
        }
        guard input.strengthDaysPerWeek <= open.count else {
            throw PlanningInputError.tooManySessions(requested: input.strengthDaysPerWeek, available: open.count)
        }
        // Spread strength days evenly across open days.
        var strength = Set<Int>()
        for i in 0..<input.strengthDaysPerWeek {
            strength.insert(open[i * open.count / input.strengthDaysPerWeek].index)
        }
        // Cardio prefers non-strength open days, then doubles up on strength days.
        let cardioOrder = open.filter { !strength.contains($0.index) } + open.filter { strength.contains($0.index) }
        let cardio = Set(cardioOrder.prefix(input.cardioDaysPerWeek).map(\.index))
        let slots = days.map { d -> PlanningDaySlot in
            var kinds: [PlanningSessionKind] = []
            if strength.contains(d.index) { kinds.append(.strength) }
            if cardio.contains(d.index) { kinds.append(.cardio) }
            if kinds.isEmpty { kinds = [.rest] }
            return PlanningDaySlot(dayIndex: d.index, weekday: d.weekday, kinds: kinds)
        }
        return PlanningOutput(slots: slots)
    }
}
