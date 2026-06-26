import Foundation

public struct WeeklyPlan: Sendable, Equatable {
    public let days: [DayOutline]
    public let generatedAt: Date

    public struct DayOutline: Sendable, Equatable, Identifiable {
        public let id: String
        public let date: Date
        public let label: String
        public let sessionKind: CoachSessionKind?
        public let isHard: Bool
        public let isRest: Bool
        public let isToday: Bool
        public let isCompleted: Bool
        public let isFuture: Bool

        public init(date: Date, label: String, sessionKind: CoachSessionKind? = nil,
                    isHard: Bool = false, isRest: Bool = true, isToday: Bool = false,
                    isCompleted: Bool = false, isFuture: Bool = false) {
            self.id = ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: .withFullDate)
            self.date = date
            self.label = label
            self.sessionKind = sessionKind
            self.isHard = isHard
            self.isRest = isRest
            self.isToday = isToday
            self.isCompleted = isCompleted
            self.isFuture = isFuture
        }
    }

    public var tomorrow: DayOutline? {
        days.first { $0.isFuture && Calendar.current.isDate($0.date, inSameDayAs: Calendar.current.date(byAdding: .day, value: 1, to: generatedAt) ?? generatedAt) }
    }

    public var today: DayOutline? {
        days.first(where: \.isToday)
    }

    public var historyDays: [DayOutline] {
        days.filter { !$0.isFuture }.sorted { $0.date < $1.date }
    }

    public var futureDays: [DayOutline] {
        days.filter(\.isFuture).sorted { $0.date < $1.date }
    }

    public var currentWeekDays: [DayOutline] {
        let cal = Calendar.current
        let start = WeeklyStats.weekStart(now: generatedAt)
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        return days
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }
    }

    public var completedDaysInGeneratedWeek: [DayOutline] {
        currentWeekDays.filter(\.isCompleted)
    }

    public var remainingCalendarWeekDays: [DayOutline] {
        currentWeekDays.filter(\.isFuture)
    }

    public static func generate(from facts: CoachFacts, trainingDaysTarget: Int = 2) -> WeeklyPlan {
        let cal = Calendar.current
        let today = cal.startOfDay(for: facts.referenceDate)
        var days: [DayOutline] = []

        let completedDays = Set(facts.rolling7dCompletedEvents.map { cal.startOfDay(for: $0.start) })
        let hardDays = Set(facts.rolling7dCompletedEvents.filter(\.isHard).map { cal.startOfDay(for: $0.start) })
        let strengthDays = Set(facts.rolling7dCompletedEvents.filter(\.isStrength).map { cal.startOfDay(for: $0.start) })

        // History: -6...0 (past 7 days including today)
        for offset in -6...0 {
            let date = cal.date(byAdding: .day, value: offset, to: today) ?? today
            let isToday = offset == 0
            let isCompleted = completedDays.contains(date)
            let wasHard = hardDays.contains(date)
            let wasStrength = strengthDays.contains(date)

            let label: String
            let sessionKind: CoachSessionKind?
            if wasStrength { label = "Strength"; sessionKind = .strength }
            else if wasHard { label = "Cardio"; sessionKind = .moderateAerobic }
            else if isCompleted { label = "Easy"; sessionKind = .easyAerobic }
            else { label = "—"; sessionKind = nil }

            days.append(DayOutline(
                date: date, label: label, sessionKind: sessionKind,
                isHard: wasHard, isRest: !isCompleted,
                isToday: isToday, isCompleted: isCompleted, isFuture: false
            ))
        }

        // Future: +1...+6 (next 6 days)
        var projectedWeekStart = WeeklyStats.weekStart(now: facts.referenceDate)
        var projectedStrengthDays = strengthDays.filter { $0 >= projectedWeekStart && $0 <= today }.count
        var projectedAerobicMinutes = facts.weeklyBalance.moderateEquivalentMinutes
        var projectedHardDays = hardDays

        for offset in 1...6 {
            let date = cal.date(byAdding: .day, value: offset, to: today) ?? today
            let weekStart = WeeklyStats.weekStart(now: date)
            if weekStart != projectedWeekStart {
                projectedWeekStart = weekStart
                projectedStrengthDays = 0
                projectedAerobicMinutes = 0
            }

            let futureKind = futureSessionKind(
                on: date,
                facts: facts,
                projectedStrengthDays: projectedStrengthDays,
                projectedAerobicMinutes: projectedAerobicMinutes,
                projectedHardDays: projectedHardDays,
                trainingDaysTarget: trainingDaysTarget,
                calendar: cal
            )
            let futureHard = isPlannedHard(futureKind)

            days.append(DayOutline(
                date: date, label: label(for: futureKind), sessionKind: futureKind,
                isHard: futureHard, isRest: futureKind == .rest,
                isToday: false, isCompleted: false, isFuture: true
            ))

            if futureKind == .strength { projectedStrengthDays += 1 }
            projectedAerobicMinutes += plannedModerateEquivalentMinutes(for: futureKind)
            if futureHard { projectedHardDays.insert(date) }
        }

        return WeeklyPlan(days: days, generatedAt: facts.referenceDate)
    }

    private static func futureSessionKind(on date: Date,
                                          facts: CoachFacts,
                                          projectedStrengthDays: Int,
                                          projectedAerobicMinutes: Double,
                                          projectedHardDays: Set<Date>,
                                          trainingDaysTarget: Int,
                                          calendar: Calendar) -> CoachSessionKind {
        let aerobicMinutesTarget = 150.0
        let strengthNeeded = projectedStrengthDays < trainingDaysTarget
        let aerobicNeeded = projectedAerobicMinutes < aerobicMinutesTarget
        let priorHardStreak = hardStreak(endingBefore: date, hardDays: projectedHardDays, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1,
                                     to: calendar.startOfDay(for: facts.referenceDate)) ?? date
        let poorReadinessApplies = facts.readiness?.isPoor == true
            && calendar.isDate(date, inSameDayAs: tomorrow)
        let recoveryNeeded = poorReadinessApplies || priorHardStreak >= 3

        if recoveryNeeded { return .recovery }

        let canPlanStrength = strengthNeeded
            && priorHardStreak == 0
            && strengthRecoveryEligible(on: date, facts: facts, calendar: calendar)
        if canPlanStrength { return .strength }

        if aerobicNeeded {
            return priorHardStreak >= 2 ? .easyAerobic : .moderateAerobic
        }

        if strengthNeeded { return .recovery }
        return .rest
    }

    private static func strengthRecoveryEligible(on date: Date,
                                                 facts: CoachFacts,
                                                 calendar: Calendar) -> Bool {
        guard let window = facts.recovery.wholeBody else { return true }
        let plannedMidday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        return plannedMidday >= window.hardEligibleAt
    }

    private static func hardStreak(endingBefore date: Date,
                                   hardDays: Set<Date>,
                                   calendar: Calendar) -> Int {
        guard var cursor = calendar.date(byAdding: .day, value: -1, to: date) else { return 0 }
        var streak = 0
        while hardDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private static func label(for kind: CoachSessionKind) -> String {
        switch kind {
        case .strength: return "Strength"
        case .easyAerobic: return "Easy aerobic"
        case .moderateAerobic: return "Cardio"
        case .vo2Intervals: return "VO₂ intervals"
        case .recovery: return "Recovery"
        case .rest: return "Rest"
        case .assessment: return "Assessment"
        }
    }

    private static func isPlannedHard(_ kind: CoachSessionKind) -> Bool {
        switch kind {
        case .strength, .vo2Intervals: return true
        case .easyAerobic, .moderateAerobic, .recovery, .rest, .assessment: return false
        }
    }

    private static func plannedModerateEquivalentMinutes(for kind: CoachSessionKind) -> Double {
        switch kind {
        case .easyAerobic: return 12.5
        case .moderateAerobic: return 35
        case .vo2Intervals: return 70
        case .strength, .recovery, .rest, .assessment: return 0
        }
    }
}
