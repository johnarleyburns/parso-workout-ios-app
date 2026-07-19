import Foundation

/// The muscle-group split a planned strength day trains. Used to (a) rotate
/// consecutive strength days across different muscles (splits — ramosCampoSplit2024)
/// so per-muscle recovery is respected, and (b) generate a focus-specific exercise
/// list. `.fullBody` is the low-frequency default (≤3 strength days/week).
public enum StrengthFocus: String, Sendable, Equatable {
    case fullBody
    case upper
    case lower

    public var label: String {
        switch self {
        case .fullBody: return "Full body"
        case .upper: return "Upper body"
        case .lower: return "Lower body"
        }
    }

    /// Movement patterns this focus programs (a subset of the full-body list).
    var patterns: [MovementPattern] {
        switch self {
        case .fullBody:
            return [.squat, .horizontalPush, .horizontalPull, .hinge,
                    .verticalPush, .verticalPull, .core, .locomotion]
        case .upper:
            return [.horizontalPush, .horizontalPull, .verticalPush, .verticalPull, .core]
        case .lower:
            return [.squat, .hinge, .locomotion, .core]
        }
    }

    /// Body parts this focus loads — consulted against per-body-part recovery windows
    /// so a focus can't be scheduled while its muscles are still recovering.
    var bodyParts: Set<BodyPart> {
        switch self {
        case .fullBody: return Set(BodyPart.allCases)
        case .upper: return [.chest, .back, .shoulders, .biceps, .triceps]
        case .lower: return [.legs, .calves]
        }
    }
}

/// A session planned for a specific day.
public struct PlannedSession: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: CoachSessionKind
    public let label: String
    public let isHard: Bool
    public let isRest: Bool
    public let timingNote: String?
    /// A non-blocking coach suggestion for this session ("coach suggests, it
    /// does not proscribe") — e.g. "Consider a lighter session — 6 hard days in
    /// a row." The session itself is still scheduled exactly as the user asked;
    /// this only annotates it. Additive/nil-default.
    public let adviceNote: String?
    /// True when the coach recommends (never forces) keeping this session
    /// lighter — long observed hard streak or a poor readiness check-in.
    public let recommendsLighter: Bool
    /// Concrete cardio prescription for a planned cardio session (coach-user-control
    /// Phase 3/4): duration and target HR zone, so a planned cardio day opens a
    /// real detail instead of a bare label. Additive/nil-default.
    public let cardioDurationMinutes: Int?
    /// Target heart-rate zone (1–5, `CardioMath.hrZone` bands) for planned cardio.
    public let cardioZone: Int?
    /// For a *history* (completed) session: the id of the real logged workout it
    /// describes, so the UI can navigate to that workout's summary. nil for
    /// planned/future sessions. Additive/nil-default.
    public let sourceWorkoutId: UUID?
    /// Concrete strength prescription for a planned strength day (issue 6). When
    /// present, the planned-day preview renders the full per-exercise list
    /// (sets × rep ladder + RIR) instead of a single generic line. Additive/nil-default
    /// so existing callers and any decoded data keep working.
    public let exercises: [CoachSession.RecommendedExercise]?
    /// The muscle-group focus of a planned strength day (issue 7). `nil` for
    /// non-strength days or when no split is in effect (full-body default).
    public let focus: StrengthFocus?

    public init(id: String, kind: CoachSessionKind, label: String,
                isHard: Bool = false, isRest: Bool = true,
                timingNote: String? = nil,
                adviceNote: String? = nil,
                recommendsLighter: Bool = false,
                cardioDurationMinutes: Int? = nil,
                cardioZone: Int? = nil,
                sourceWorkoutId: UUID? = nil,
                exercises: [CoachSession.RecommendedExercise]? = nil,
                focus: StrengthFocus? = nil) {
        self.id = id
        self.kind = kind
        self.label = label
        self.isHard = isHard
        self.isRest = isRest
        self.timingNote = timingNote
        self.adviceNote = adviceNote
        self.recommendsLighter = recommendsLighter
        self.cardioDurationMinutes = cardioDurationMinutes
        self.cardioZone = cardioZone
        self.sourceWorkoutId = sourceWorkoutId
        self.exercises = exercises
        self.focus = focus
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
        // Every logged workout on a day gets its own chip (coach-user-control
        // Phase 4): a strength AM + boxing PM day lists both, each linked back to
        // its real workout via `sourceWorkoutId`. Past cardio keeps the *real*
        // logged modality (a Boxing session reads "Boxing", never the generic
        // "Easy aerobic" bucket).
        var strengthEventsByDay: [Date: [TrainingEvent]] = [:]
        var cardioEventsByDay: [Date: [TrainingEvent]] = [:]

        for event in facts.rolling7dCompletedEvents {
            let d = cal.startOfDay(for: event.start)
            completedDays.insert(d)
            if event.isHard { hardDays.insert(d) }
            if event.isStrength {
                strengthDays.insert(d)
                strengthEventsByDay[d, default: []].append(event)
            }
            if event.isAerobic {
                cardioEventsByDay[d, default: []].append(event)
            }
        }

        // History: -6...0 (past 7 days including today)
        for offset in -6...0 {
            let date = cal.date(byAdding: .day, value: offset, to: today) ?? today
            let isToday = offset == 0
            let isCompleted = completedDays.contains(date)

            var sessions: [PlannedSession] = []
            for (idx, event) in (strengthEventsByDay[date] ?? []).sorted(by: { $0.start < $1.start }).enumerated() {
                sessions.append(PlannedSession(id: "h-\(date)-strength-\(idx)",
                                                kind: .strength, label: "Strength",
                                                isHard: true, isRest: false,
                                                sourceWorkoutId: event.id))
            }
            for (idx, event) in (cardioEventsByDay[date] ?? []).sorted(by: { $0.start < $1.start }).enumerated() {
                let kind: CoachSessionKind = event.isHard ? .moderateAerobic : .easyAerobic
                sessions.append(PlannedSession(id: "h-\(date)-cardio-\(idx)",
                                                kind: kind,
                                                label: historyModalityLabel(for: event) ?? cardioLabel(kind),
                                                isHard: event.isHard, isRest: false,
                                                sourceWorkoutId: event.id))
            }

            // A multi-session day describes every session (issue 7); it must
            // never collapse to a bare weekday name like "Thu".
            let label = sessions.isEmpty ? "—" : dayLabel(forSessions: sessions)

            days.append(DayOutline(
                date: date, label: label, sessions: sessions,
                isToday: isToday, isCompleted: isCompleted, isFuture: false,
                isPast: offset < 0
            ))
        }

        // --- Future planning: remainder of current week + full next week ---

        let currentWeekStart = WeeklyStats.weekStart(now: facts.referenceDate)
        let nextWeekStart = cal.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart
        let planningEnd = cal.date(byAdding: .day, value: 14, to: currentWeekStart) ?? currentWeekStart

        // Accumulate projected state: strength days left for current week, etc.
        // Effective strength floor (issue 7): honor the stored preference AND infer
        // the user's real cadence from history — a 5×/week lifter with a stale
        // preference of 2 should still see ~5 planned strength days. The observed
        // count is the distinct strength days in the trailing 7 days. Inference only
        // *raises* the floor; the stored preference stays authoritative as a minimum.
        let observedWeeklyStrengthDays = Set(
            facts.rolling7dCompletedEvents
                .filter(\.isStrength)
                .map { cal.startOfDay(for: $0.start) }
        ).count
        let strengthFloor = min(6, max(schedulePreferences.strengthDaysPerWeek, observedWeeklyStrengthDays))
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

        // Split mode (issue 7): at ≥4 strength days/week the coach rotates
        // upper/lower focuses so consecutive strength days train different muscles
        // (ramosCampoSplit2024) while per-muscle recovery is respected
        // (parejaBlancoRecovery2020). Below that it keeps whole-body sessions.
        let useSplit = strengthFloor >= 4
        var nextFocus: StrengthFocus = .upper

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

            let plannedFocus: StrengthFocus = useSplit ? nextFocus : .fullBody
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
                restPreference: schedulePreferences.restPreference,
                desiredSetsPerExercise: schedulePreferences.desiredSetsPerExercise,
                useSplit: useSplit,
                focus: plannedFocus,
                facts: facts,
                calendar: cal
            )

            let label = dayLabel(forSessions: sessions)
            let dayOutline = DayOutline(
                date: date, label: label, sessions: sessions,
                isToday: false, isCompleted: false, isFuture: true
            )
            days.append(dayOutline)

            // Update projections. Only genuinely hard sessions (hard strength,
            // vigorous/interval cardio) mark a hard day — planned easy/moderate
            // cardio must not trip recovery logic and eat the user's strength
            // days ("coach suggests" plan, Phase 3).
            for s in sessions {
                if s.kind == .strength {
                    projectedStrengthDays += 1
                    lastStrengthDate = date
                    // Rotate the split focus off the focus actually scheduled, so
                    // upper/lower alternate even when a blocked focus was swapped.
                    if useSplit, let f = s.focus {
                        nextFocus = (f == .upper) ? .lower : .upper
                    }
                }
                if s.isHard {
                    projectedHardDays.insert(date)
                }
                if s.kind == .easyAerobic || s.kind == .moderateAerobic || s.kind == .vo2Intervals {
                    projectedAerobicMinutes += plannedModerateEquivalentMinutes(for: s.kind)
                    projectedCardioDays += 1
                }
            }
        }

        // Augment today with coach-planned sessions when nothing was completed
        // yet today — the history loop only records completed work, and the future
        // loop starts at offset 1 (tomorrow), so today can land with an empty "—"
        // label even though the coach has a prescription for it.
        if let todayIdx = days.firstIndex(where: { $0.isToday }),
           days[todayIdx].sessions.isEmpty {
            let planned = futureSessions(
                on: days[todayIdx].date,
                projectedStrengthDays: currentWeekStrengthDone,
                projectedCardioDays: currentWeekCardioDaysDone,
                projectedAerobicMinutes: currentWeekAerobicMinutes,
                projectedHardDays: hardDays,
                lastStrengthDate: lastStrengthDate,
                lastLowerBodyCardioDate: lastLowerBodyCardioDate,
                strengthFloor: strengthFloor,
                cardioDayTarget: cardioDayTarget,
                aerobicMinutesTarget: aerobicMinutesTarget,
                allowsTwoADays: schedulePreferences.allowsTwoADays,
                sameDayCardioTiming: schedulePreferences.sameDayCardioTiming,
                restPreference: schedulePreferences.restPreference,
                desiredSetsPerExercise: schedulePreferences.desiredSetsPerExercise,
                useSplit: useSplit,
                focus: useSplit ? .upper : .fullBody,
                facts: facts,
                calendar: cal
            )
            let label = dayLabel(forSessions: planned)
            days[todayIdx] = DayOutline(
                date: days[todayIdx].date, label: label, sessions: planned,
                isToday: true, isCompleted: days[todayIdx].isCompleted,
                isFuture: false, isPast: false
            )
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
        restPreference: RestPreference,
        desiredSetsPerExercise: Int,
        useSplit: Bool,
        focus: StrengthFocus,
        facts: CoachFacts,
        calendar: Calendar
    ) -> [PlannedSession] {
        var sessions: [PlannedSession] = []

        // Fixed rest days take priority — short-circuit before any training check.
        // They are the ONLY true non-training days: the coach never converts a
        // scheduled training day into a forced Recovery day ("coach suggests, it
        // does not proscribe").
        if isRestDay(date: date, restPreference: restPreference, calendar: calendar) {
            return [PlannedSession(id: "f-\(date)-rest", kind: .rest, label: "Rest",
                                    isHard: false, isRest: true)]
        }

        let strengthNeeded = projectedStrengthDays < strengthFloor
        let cardioNeeded = projectedCardioDays < cardioDayTarget
            || projectedAerobicMinutes < aerobicMinutesTarget
        let priorHardStreak = hardStreak(endingBefore: date, hardDays: projectedHardDays, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1,
                                     to: calendar.startOfDay(for: facts.referenceDate)) ?? date
        let poorReadinessApplies = facts.readiness?.isPoor == true
            && calendar.isDate(date, inSameDayAs: tomorrow)

        // Recommend, don't force, recovery (meeusenOvertraining2013). Athletes
        // routinely train 6 hard days a week, so the nudge only appears past a
        // genuinely long observed hard streak (or a poor readiness check-in) —
        // and it NEVER replaces the day's scheduled sessions.
        let recommendsLighter = poorReadinessApplies || priorHardStreak >= 6
        let adviceNote: String?
        if poorReadinessApplies {
            adviceNote = "Readiness is low — consider keeping today lighter."
        } else if recommendsLighter {
            adviceNote = "Consider a lighter session — \(priorHardStreak) hard days in a row."
        } else {
            adviceNote = nil
        }

        // Strength eligibility. Recovery/spacing gates may *shift* a strength day,
        // but the user's weekly target wins: when the remaining non-rest days of
        // this week can no longer absorb the deficit, strength is scheduled anyway.
        var planFocus: StrengthFocus = useSplit ? focus : .fullBody
        var canStrength = false
        if strengthNeeded {
            if useSplit {
                // Split mode allows consecutive strength days as long as this day's
                // focus trains recovered muscles (parejaBlancoRecovery2020); a blocked
                // focus first tries the alternate focus rather than dropping the day.
                if focusRecoveryEligible(planFocus, on: date, facts: facts, calendar: calendar) {
                    canStrength = true
                } else {
                    let alternate: StrengthFocus = planFocus == .upper ? .lower : .upper
                    if focusRecoveryEligible(alternate, on: date, facts: facts, calendar: calendar) {
                        canStrength = true
                        planFocus = alternate
                    }
                }
            } else {
                canStrength = priorHardStreak == 0
                    && strengthRecoveryEligible(on: date, facts: facts, calendar: calendar)
                    && (lastStrengthDate == nil || calendar.dateComponents([.day], from: lastStrengthDate!, to: date).day! >= 1)
            }
            if !canStrength && mustScheduleStrength(on: date,
                                                    deficit: strengthFloor - projectedStrengthDays,
                                                    restPreference: restPreference,
                                                    calendar: calendar) {
                canStrength = true
            }
        }

        if canStrength {
            let exercises = CoachSession.strengthExercises(
                facts: facts,
                patterns: planFocus.patterns,
                desiredSetsPerExercise: desiredSetsPerExercise
            )
            sessions.append(PlannedSession(id: "f-\(date)-strength",
                                            kind: .strength,
                                            label: useSplit ? "Strength · \(planFocus.label)" : "Strength",
                                            isHard: true, isRest: false,
                                            adviceNote: adviceNote,
                                            recommendsLighter: recommendsLighter,
                                            exercises: exercises.isEmpty ? nil : exercises,
                                            focus: planFocus))
        }

        // Cardio: a cardio day the user asked for is never dropped because of
        // projected load. With two-a-days on, cardio pairs with strength on every
        // non-rest day until the weekly targets are met — the coach modulates
        // intensity (easy vs moderate) instead of dropping a modality.
        if cardioNeeded && (sessions.isEmpty || allowsTwoADays) {
            let cardioKind: CoachSessionKind =
                (recommendsLighter || priorHardStreak >= 2) ? .easyAerobic : .moderateAerobic
            sessions.append(plannedCardio(id: "f-\(date)-cardio", kind: cardioKind,
                                          adviceNote: sessions.isEmpty ? adviceNote : nil,
                                          recommendsLighter: recommendsLighter))
        }

        // If nothing scheduled, rest
        if sessions.isEmpty {
            sessions.append(PlannedSession(id: "f-\(date)-rest", kind: .rest, label: "Rest",
                                            isHard: false, isRest: true))
        }

        return sessions
    }

    /// A planned cardio session carrying a concrete prescription (duration +
    /// target HR zone) so the planned-day preview renders a real detail.
    private static func plannedCardio(id: String, kind: CoachSessionKind,
                                      adviceNote: String?,
                                      recommendsLighter: Bool) -> PlannedSession {
        let (minutes, zone): (Int, Int)
        switch kind {
        case .easyAerobic: (minutes, zone) = (25, 2)
        case .moderateAerobic: (minutes, zone) = (35, 3)
        case .vo2Intervals: (minutes, zone) = (35, 5)
        default: (minutes, zone) = (25, 2)
        }
        return PlannedSession(id: id, kind: kind, label: cardioLabel(kind),
                              isHard: kind == .vo2Intervals, isRest: false,
                              adviceNote: adviceNote,
                              recommendsLighter: recommendsLighter,
                              cardioDurationMinutes: minutes,
                              cardioZone: zone)
    }

    /// True when the user's weekly strength target can no longer be met unless a
    /// strength session is scheduled on this date — the remaining non-rest days of
    /// the week (including this one) are fewer than or equal to the deficit. The
    /// user's stated days/week trump the coach's automatic recovery logic.
    private static func mustScheduleStrength(on date: Date, deficit: Int,
                                             restPreference: RestPreference,
                                             calendar: Calendar) -> Bool {
        guard deficit > 0 else { return false }
        let weekStart = WeeklyStats.weekStart(now: date)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return false }
        var remaining = 0
        var cursor = calendar.startOfDay(for: date)
        while cursor < weekEnd {
            if !isRestDay(date: cursor, restPreference: restPreference, calendar: calendar) {
                remaining += 1
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? weekEnd
        }
        return deficit >= remaining
    }

    /// A split focus is eligible on a date when none of the body parts it trains are
    /// still inside their per-part recovery window (parejaBlancoRecovery2020). This
    /// lets an upper day follow a lower day (different muscles) while still blocking a
    /// same-muscle repeat before it has recovered.
    private static func focusRecoveryEligible(_ focus: StrengthFocus, on date: Date,
                                              facts: CoachFacts, calendar: Calendar) -> Bool {
        let plannedMidday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        for part in focus.bodyParts {
            if let window = facts.recovery.byBodyPart[part], plannedMidday < window.hardEligibleAt {
                return false
            }
        }
        return true
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

    private static func dayLabel(forSessions sessions: [PlannedSession]) -> String {
        if sessions.isEmpty { return "—" }
        let names = sessions.map(\.label)
        return names.joined(separator: " · ")
    }

    private static func historyModalityLabel(for event: TrainingEvent) -> String? {
        switch event.kind {
        case .aerobic(let details), .intervals(let details):
            return details.modality == .other ? nil : details.modality.displayName
        default:
            return nil
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

    /// Answers whether a date should be a rest day based on the user's configured preference.
    private static func isRestDay(date: Date, restPreference: RestPreference,
                                   calendar: Calendar) -> Bool {
        switch restPreference {
        case .fixed(let days):
            guard let weekday = Weekday(from: date, calendar: calendar) else { return false }
            return days.contains(weekday)
        case .rolling(let everyNDays):
            // Rolling rest: after N consecutive training days, take a rest day.
            // The (N+1)-day cycle repeats: rest on day N, 2N+1, 3N+2, …
            let weekStart = WeeklyStats.weekStart(now: date)
            let daysSinceWeekStart = calendar.dateComponents([.day], from: weekStart, to: date).day ?? 0
            let cycleLength = everyNDays + 1
            return daysSinceWeekStart > 0 && (daysSinceWeekStart % cycleLength) == everyNDays
        }
    }
}
