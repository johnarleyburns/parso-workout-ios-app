import Foundation

// MARK: - Weekday (calendar-safe, not array-offset–based)

public enum Weekday: Int, Codable, Sendable, CaseIterable, Hashable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    public var displayName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    public init?(from date: Date, calendar: Calendar = .current) {
        let wd = calendar.component(.weekday, from: date)
        self.init(rawValue: wd)
    }
}

// MARK: - RestPreference

public enum RestPreference: Codable, Sendable, Equatable {
    case fixed(days: Set<Weekday>)
    case rolling(everyNDays: Int)

    public var displayName: String {
        switch self {
        case .fixed(let days):
            if days.isEmpty { return "None" }
            return days.sorted(by: { $0.rawValue < $1.rawValue }).map(\.displayName).joined(separator: ", ")
        case .rolling(let n):
            return "Every \(n) days"
        }
    }

    public static let defaultRolling = RestPreference.rolling(everyNDays: 3)
}

// MARK: - SameDayCardioTiming

public enum SameDayCardioTiming: String, Codable, Sendable, CaseIterable {
    case afterStrength
    case separateLater
}

// MARK: - CoachSchedulePreferences

public struct CoachSchedulePreferences: Codable, Equatable, Sendable {
    public var strengthDaysPerWeek: Int
    public var cardioDaysPerWeek: Int
    public var restPreference: RestPreference
    public var allowsTwoADays: Bool
    public var sameDayCardioTiming: SameDayCardioTiming
    public var dailyStepTarget: Int
    public var excludedCoverageParts: Set<BodyPart>

    public static let `default` = CoachSchedulePreferences(
        strengthDaysPerWeek: 2,
        cardioDaysPerWeek: 3,
        restPreference: .defaultRolling,
        allowsTwoADays: false,
        sameDayCardioTiming: .afterStrength,
        excludedCoverageParts: [])

    public init(strengthDaysPerWeek: Int = 2,
                cardioDaysPerWeek: Int = 3,
                restPreference: RestPreference = .defaultRolling,
                allowsTwoADays: Bool = false,
                sameDayCardioTiming: SameDayCardioTiming = .afterStrength,
                dailyStepTarget: Int = 8_000,
                excludedCoverageParts: Set<BodyPart> = []) {
        self.strengthDaysPerWeek = min(5, max(2, strengthDaysPerWeek))
        self.cardioDaysPerWeek = min(7, max(0, cardioDaysPerWeek))
        self.restPreference = restPreference
        self.allowsTwoADays = allowsTwoADays
        self.sameDayCardioTiming = sameDayCardioTiming
        self.dailyStepTarget = min(20_000, max(2_000, dailyStepTarget))
        self.excludedCoverageParts = excludedCoverageParts
    }

    // MARK: Constrained setters for use in UI

    public func withStrengthDays(_ d: Int) -> CoachSchedulePreferences {
        var copy = self
        copy.strengthDaysPerWeek = min(5, max(2, d))
        return copy
    }

    public func withCardioDays(_ d: Int) -> CoachSchedulePreferences {
        var copy = self
        copy.cardioDaysPerWeek = min(7, max(0, d))
        return copy
    }

    public func withRestPreference(_ r: RestPreference) -> CoachSchedulePreferences {
        var copy = self
        copy.restPreference = r
        return copy
    }

    public func withTwoADays(_ allowed: Bool) -> CoachSchedulePreferences {
        var copy = self
        copy.allowsTwoADays = allowed
        return copy
    }

    public func withSameDayCardioTiming(_ t: SameDayCardioTiming) -> CoachSchedulePreferences {
        var copy = self
        copy.sameDayCardioTiming = t
        return copy
    }

    public func withDailyStepTarget(_ target: Int) -> CoachSchedulePreferences {
        var copy = self
        copy.dailyStepTarget = min(20_000, max(2_000, target))
        return copy
    }
}
