import Foundation

/// A session planned for a specific day.
public struct PlannedSession: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: CoachSessionKind
    public let label: String
    public let isHard: Bool
    public let isRest: Bool
    public let timingNote: String?

    public init(id: String, kind: CoachSessionKind, label: String,
                isHard: Bool = false, isRest: Bool = true,
                timingNote: String? = nil) {
        self.id = id
        self.kind = kind
        self.label = label
        self.isHard = isHard
        self.isRest = isRest
        self.timingNote = timingNote
    }
}

public struct WeeklyPlan: Sendable, Equatable {
    public let days: [DayOutline]
    public let generatedAt: Date

    public struct DayOutline: Sendable, Equatable, Identifiable {
        public let id: String
        public let date: Date
        public let label: String
        public let sessions: [PlannedSession]
        public let isToday: Bool
        public let isCompleted: Bool
        public let isFuture: Bool
        public let isPast: Bool

        /// Convenience: first session kind (for backward compat)
        public var sessionKind: CoachSessionKind? { sessions.first?.kind }
        public var isHard: Bool { sessions.contains(where: \.isHard) }
        public var isRest: Bool { sessions.allSatisfy(\.isRest) }

        public init(date: Date, label: String, sessions: [PlannedSession] = [],
                    isToday: Bool = false, isCompleted: Bool = false,
                    isFuture: Bool = false, isPast: Bool = false) {
            self.id = ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: .withFullDate)
            self.date = date
            self.label = label
            self.sessions = sessions
            self.isToday = isToday
            self.isCompleted = isCompleted
            self.isFuture = isFuture
            self.isPast = isPast
        }
    }

    public var tomorrow: DayOutline? {
        let cal = Calendar.current
        let tomorrowDate = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: generatedAt)) ?? generatedAt
        return days.first { $0.isFuture && cal.isDate($0.date, inSameDayAs: tomorrowDate) }
    }

    public var today: DayOutline? {
        days.first(where: \.isToday)
    }

    public var futureDays: [DayOutline] {
        days.filter(\.isFuture).sorted { $0.date < $1.date }
    }

    public var historyDays: [DayOutline] {
        days.filter { !$0.isFuture }.sorted { $0.date < $1.date }
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

    public var nextWeekDays: [DayOutline] {
        let cal = Calendar.current
        let currentStart = WeeklyStats.weekStart(now: generatedAt)
        let nextStart = cal.date(byAdding: .day, value: 7, to: currentStart) ?? currentStart
        let nextEnd = cal.date(byAdding: .day, value: 7, to: nextStart) ?? nextStart
        return days
            .filter { $0.date >= nextStart && $0.date < nextEnd }
            .sorted { $0.date < $1.date }
    }

    public var plannedCurrentWeekSessions: [(day: DayOutline, sessions: [PlannedSession])] {
        remainingCalendarWeekDays.compactMap { day in
            let planned = day.sessions.filter { s in !s.isRest || s.kind == .rest }
            guard !planned.isEmpty else { return nil }
            return (day, planned)
        }
    }

    public var plannedNextWeekSessions: [(day: DayOutline, sessions: [PlannedSession])] {
        nextWeekDays.compactMap { day in
            let planned = day.sessions.filter { s in !s.isRest || s.kind == .rest }
            guard !planned.isEmpty else { return nil }
            return (day, planned)
        }
    }

    public static func generate(from facts: CoachFacts,
                                 schedulePreferences: CoachSchedulePreferences = .default) -> WeeklyPlan {
        let cal = Calendar.current
        let today = cal.startOfDay(for: facts.referenceDate)
        var days: [DayOutline] = []

        // Completion and type tracking from rolling 7-day events
        var completedDays = Set<Date>()
        var hardDays = Set<Date>()
        var strengthDays = Set<Date>()
        var cardioEventsByDay: [Date: (hasHard: Bool, kind: CoachSessionKind)] = [:]

        for event in facts.rolling7dCompletedEvents {
            let d = cal.startOfDay(for: event.start)
            completedDays.insert(d)
            if event.isHard { hardDays.insert(d) }
            if event.isStrength { strengthDays.insert(d) }
            if event.isAerobic {
                let cur = cardioEventsByDay[d]
                let isHard = event.isHard
                let kind: CoachSessionKind = isHard ? .moderateAerobic : .easyAerobic
                if cur == nil || isHard {
                    cardioEventsByDay[d] = (hasHard: isHard, kind: kind)
                }
            }
        }

        // History: -6...0 (past 7 days including today)
        for offset in -6...0 {
            let date = cal.date(byAdding: .day, value: offset, to: today) ?? today
            let isToday = offset == 0
            let isCompleted = completedDays.contains(date)
            let wasStrength = strengthDays.contains(date)
            let cardioInfo = cardioEventsByDay[date]

            var sessions: [PlannedSession] = []
            if wasStrength {
                sessions.append(PlannedSession(id: "h-\(date)-strength",
                                                kind: .strength, label: "Strength",
                                                isHard: true, isRest: false))
            }
            if let cardio = cardioInfo {
                sessions.append(PlannedSession(id: "h-\(date)-cardio",
                                                kind: cardio.kind, label: cardioLabel(cardio.kind),
                                                isHard: cardio.kind == .moderateAerobic, isRest: false))
            }

            let label: String
            if wasStrength && cardioInfo != nil { label = dayLabel(for: date, calendar: cal) }
            else if wasStrength { label = "Strength" }
            else if cardioInfo != nil { label = cardioLabel(cardioInfo!.kind) }
            else { label = "—" }

            days.append(DayOutline(
                date: date, label: label, sessions: sessions,
                isToday: isToday, isCompleted: isCompleted, isFuture: false,
                isPast: offset < 0
            ))
        }

        // --- Future planning: remainder of current week + full next week ---

        let currentWeekStart = WeeklyStats.weekStart(now: facts.referenceDate)
        let nextWeekStart = cal.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart
        let planningEnd = cal.date(byAdding: .day, value: 13, to: currentWeekStart) ?? currentWeekStart

        // Accumulate projected state: strength days left for current week, etc.
        let strengthFloor = schedulePreferences.strengthDaysPerWeek
        let cardioDayTarget = schedulePreferences.cardioDaysPerWeek
        let aerobicMinutesTarget = 150.0

        // Count what's already done in the current week
        let currentWeekStrengthDone = strengthDays.filter { $0 >= currentWeekStart && $0 < nextWeekStart && $0 <= today }.count
        let currentWeekCardioDaysDone = Set(cardioEventsByDay.keys.filter { $0 >= currentWeekStart && $0 < nextWeekStart && $0 <= today }).count
        let currentWeekAerobicMinutes = facts.weeklyBalance.moderateEquivalentMinutes

        var projectedStrengthDays = currentWeekStrengthDone
        var projectedCardioDays = currentWeekCardioDaysDone
        var projectedHardDays = hardDays
        var projectedAerobicMinutes = currentWeekAerobicMinutes
        var lastStrengthDate: Date?
        var lastLowerBodyCardioDate: Date?

        // Track last strength date from history
        let sortedStrength = strengthDays.filter { $0 <= today }.sorted()
        lastStrengthDate = sortedStrength.last

        // Track last lower-body cardio
        for event in facts.rolling7dCompletedEvents where event.isAerobic && event.isHard {
            lastLowerBodyCardioDate = cal.startOfDay(for: event.start)
        }

        var weekResetOffset = nextWeekStart

        // Future days: current week remainder + full next week
        var futureOffset = 1
        while true {
            let date = cal.date(byAdding: .day, value: futureOffset, to: today) ?? today
            guard date < planningEnd else { break }
            futureOffset += 1

            // Reset weekly counters when entering a new week
            if date >= weekResetOffset {
                projectedStrengthDays = 0
                projectedCardioDays = 0
                projectedAerobicMinutes = 0
                weekResetOffset = cal.date(byAdding: .day, value: 7, to: weekResetOffset) ?? weekResetOffset
            }

            let sessions = futureSessions(
                on: date,
                projectedStrengthDays: projectedStrengthDays,
                projectedCardioDays: projectedCardioDays,
                projectedAerobicMinutes: projectedAerobicMinutes,
                projectedHardDays: projectedHardDays,
                lastStrengthDate: lastStrengthDate,
                lastLowerBodyCardioDate: lastLowerBodyCardioDate,
                strengthFloor: strengthFloor,
                cardioDayTarget: cardioDayTarget,
                aerobicMinutesTarget: aerobicMinutesTarget,
                allowsTwoADays: schedulePreferences.allowsTwoADays,
                sameDayCardioTiming: schedulePreferences.sameDayCardioTiming,
                facts: facts,
                calendar: cal
            )

            let label = dayLabel(forSessions: sessions)
            let dayOutline = DayOutline(
                date: date, label: label, sessions: sessions,
                isToday: false, isCompleted: false, isFuture: true
            )
            days.append(dayOutline)

            // Update projections
            for s in sessions {
                if s.kind == .strength {
                    projectedStrengthDays += 1
                    lastStrengthDate = date
                }
                if s.isHard || s.kind == .moderateAerobic || s.kind == .vo2Intervals {
                    projectedHardDays.insert(date)
                    projectedAerobicMinutes += plannedModerateEquivalentMinutes(for: s.kind)
                }
                if s.kind == .easyAerobic || s.kind == .moderateAerobic || s.kind == .vo2Intervals {
                    projectedAerobicMinutes += plannedModerateEquivalentMinutes(for: s.kind)
                    projectedCardioDays += 1
                }
            }
        }

        return WeeklyPlan(days: days, generatedAt: facts.referenceDate)
    }

    /// Compute planned sessions for a future date, possibly two-a-day.
    private static func futureSessions(
        on date: Date,
        projectedStrengthDays: Int,
        projectedCardioDays: Int,
        projectedAerobicMinutes: Double,
        projectedHardDays: Set<Date>,
        lastStrengthDate: Date?,
        lastLowerBodyCardioDate: Date?,
        strengthFloor: Int,
        cardioDayTarget: Int,
        aerobicMinutesTarget: Double,
        allowsTwoADays: Bool,
        sameDayCardioTiming: SameDayCardioTiming,
        facts: CoachFacts,
        calendar: Calendar
    ) -> [PlannedSession] {
        var sessions: [PlannedSession] = []

        let strengthNeeded = projectedStrengthDays < strengthFloor
        let cardioNeeded = projectedCardioDays < cardioDayTarget
            || projectedAerobicMinutes < aerobicMinutesTarget
        let priorHardStreak = hardStreak(endingBefore: date, hardDays: projectedHardDays, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1,
                                     to: calendar.startOfDay(for: facts.referenceDate)) ?? date
        let poorReadinessApplies = facts.readiness?.isPoor == true
            && calendar.isDate(date, inSameDayAs: tomorrow)
        let recoveryNeeded = poorReadinessApplies || priorHardStreak >= 3

        if recoveryNeeded {
            return [PlannedSession(id: "f-\(date)-recovery", kind: .recovery, label: "Recovery",
                                    isHard: false, isRest: false)]
        }

        // Check strength eligibility: recovery window, need, spacing
        let canStrength = strengthNeeded
            && priorHardStreak == 0
            && strengthRecoveryEligible(on: date, facts: facts, calendar: calendar)
            && (lastStrengthDate == nil || calendar.dateComponents([.day], from: lastStrengthDate!, to: date).day! >= 1)

        // Avoid hard lower-body strength adjacent to hard lower-body cardio
        // (enforced by recovery gates above)

        if canStrength {
            sessions.append(PlannedSession(id: "f-\(date)-strength",
                                            kind: .strength, label: "Strength",
                                            isHard: true, isRest: false))
        }

        // Cardio session
        let canCardio = cardioNeeded
            && !projectedHardDays.contains(date)
            && (canStrength || !projectedHardDays.contains(date))

        if canCardio || (cardioNeeded && allowsTwoADays) {
            let cardioKind: CoachSessionKind = priorHardStreak >= 2 ? .easyAerobic : .moderateAerobic
            var timingNote: String? = nil
            if !sessions.isEmpty && allowsTwoADays {
                switch sameDayCardioTiming {
                case .afterStrength:
                    timingNote = "after lifting"
                case .separateLater:
                    timingNote = "later in the day"
                }
            } else if sessions.isEmpty && !canStrength && strengthNeeded {
                // Strength needed but can't do it; cardio fills the gap
                timingNote = nil
            }

            // If a strength session was scheduled, only add cardio if two-a-days allowed or no strength
            if sessions.isEmpty || allowsTwoADays {
            sessions.append(PlannedSession(id: "f-\(date)-cardio",
                                            kind: cardioKind, label: cardioLabel(cardioKind),
                                            isHard: false, isRest: false,
                                            timingNote: timingNote))
            }
        }

        // If nothing scheduled, rest
        if sessions.isEmpty {
            sessions.append(PlannedSession(id: "f-\(date)-rest", kind: .rest, label: "Rest",
                                            isHard: false, isRest: true))
        }

        return sessions
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

    private static func cardioLabel(_ kind: CoachSessionKind) -> String {
        switch kind {
        case .easyAerobic: return "Easy aerobic"
        case .moderateAerobic: return "Cardio"
        case .vo2Intervals: return "VO₂ intervals"
        default: return "Cardio"
        }
    }

    private static func dayLabel(for date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private static func dayLabel(forSessions sessions: [PlannedSession]) -> String {
        if sessions.isEmpty { return "—" }
        let names = sessions.map(\.label)
        return names.joined(separator: " · ")
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
