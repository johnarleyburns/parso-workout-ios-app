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

    public static func generate(from facts: CoachFacts, trainingDaysTarget: Int = 3) -> WeeklyPlan {
        let cal = Calendar.current
        let today = cal.startOfDay(for: facts.referenceDate)
        var days: [DayOutline] = []

        let completedDays = Set(facts.rolling7dCompletedEvents.map { cal.startOfDay(for: $0.start) })
        let hardDays = Set(facts.rolling7dCompletedEvents.filter(\.isHard).map { cal.startOfDay(for: $0.start) })
        let strengthDays = Set(facts.rolling7dCompletedEvents.filter(\.isStrength).map { cal.startOfDay(for: $0.start) })
        let aerobicDays = Set(facts.rolling7dCompletedEvents.filter(\.isAerobic).map { cal.startOfDay(for: $0.start) })

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

        let plannedStrength = days.filter { $0.sessionKind == .strength }.count
        var remainingStrength = max(0, trainingDaysTarget - plannedStrength)

        // Backfill strength into empty past slots
        for i in 0..<7 {
            guard remainingStrength > 0 else { break }
            let idx = 6 - i
            if days[idx].sessionKind == nil, idx >= 0 {
                let date = days[idx].date
                days[idx] = DayOutline(
                    date: date, label: "Strength", sessionKind: .strength,
                    isHard: true, isRest: false, isToday: days[idx].isToday,
                    isCompleted: false, isFuture: false
                )
                remainingStrength -= 1
            }
        }

        // Future: +1...+6 (next 6 days)
        let todayCompletedAerobic = aerobicDays.contains(today)
        let todayCompletedStrength = strengthDays.contains(today)

        // If today's aerobic plan is already complete, tomorrow defaults to strength
        // if strength is still below target and recovery allows.
        let strengthBelowTarget = strengthDays.count < trainingDaysTarget
        let totalStrengthCount = strengthDays.count + (todayCompletedStrength ? 0 : 0)

        for offset in 1...6 {
            let date = cal.date(byAdding: .day, value: offset, to: today) ?? today
            let isTomorrow = offset == 1

            // Determine future plan: alternate strength/aerobic with rest days
            let futureLabel: String
            let futureKind: CoachSessionKind?
            let futureHard: Bool

            if remainingStrength > 0 && offset % 2 == 0 {
                futureLabel = "Strength"
                futureKind = .strength
                futureHard = true
                remainingStrength -= 1
            } else if strengthBelowTarget && remainingStrength <= 0 && offset <= 2 {
                // Still need strength but backfill is done; suggest strength on early days
                if offset % 2 != 0 {
                    futureLabel = "Strength"
                    futureKind = .strength
                    futureHard = true
                } else {
                    futureLabel = "Rest"
                    futureKind = .rest
                    futureHard = false
                }
            } else if offset % 2 != 0 && !isTomorrow {
                futureLabel = "Cardio"
                futureKind = .moderateAerobic
                futureHard = true
            } else {

                futureLabel = isTomorrow ? "Cardio" : "Rest"
                futureKind = isTomorrow ? .moderateAerobic : .rest
                futureHard = isTomorrow
            }

            days.append(DayOutline(
                date: date, label: futureLabel, sessionKind: futureKind,
                isHard: futureHard, isRest: futureKind == .rest,
                isToday: false, isCompleted: false, isFuture: true
            ))
        }

        return WeeklyPlan(days: days, generatedAt: facts.referenceDate)
    }
}
