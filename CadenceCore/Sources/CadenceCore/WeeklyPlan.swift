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

        public init(date: Date, label: String, sessionKind: CoachSessionKind? = nil,
                    isHard: Bool = false, isRest: Bool = true, isToday: Bool = false,
                    isCompleted: Bool = false) {
            self.id = ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: .withFullDate)
            self.date = date
            self.label = label
            self.sessionKind = sessionKind
            self.isHard = isHard
            self.isRest = isRest
            self.isToday = isToday
            self.isCompleted = isCompleted
        }
    }

    public static func generate(from facts: CoachFacts, trainingDaysTarget: Int = 3) -> WeeklyPlan {
        let cal = Calendar.current
        let today = cal.startOfDay(for: facts.referenceDate)
        var days: [DayOutline] = []

        let completedDays = Set(facts.rolling7dCompletedEvents.map { cal.startOfDay(for: $0.start) })
        let hardDays = Set(facts.rolling7dCompletedEvents.filter(\.isHard).map { cal.startOfDay(for: $0.start) })
        let strengthDays = Set(facts.rolling7dCompletedEvents.filter(\.isStrength).map { cal.startOfDay(for: $0.start) })

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
                isToday: isToday, isCompleted: isCompleted
            ))
        }

        let plannedStrength = days.filter { $0.sessionKind == .strength }.count
        var remainingStrength = max(0, trainingDaysTarget - plannedStrength)

        for i in 0..<7 {
            guard remainingStrength > 0 else { break }
            let idx = 6 - i
            if days[idx].sessionKind == nil, idx >= 0 {
                let date = days[idx].date
                days[idx] = DayOutline(
                    date: date, label: "Strength", sessionKind: .strength,
                    isHard: true, isRest: false, isToday: days[idx].isToday, isCompleted: false
                )
                remainingStrength -= 1
            }
        }

        return WeeklyPlan(days: days, generatedAt: facts.referenceDate)
    }
}
