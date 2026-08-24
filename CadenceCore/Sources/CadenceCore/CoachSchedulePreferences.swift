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
    public var desiredSetsPerExercise: Int
    /// The muscle groups the coach programs toward and Home always shows a row
    /// for. Defaults to `MuscleGroup.defaultTracked` — the 13 groups the catalog
    /// can actually satisfy a weekly target for (decision D4). Anyone who wants to
    /// program adductors, the neck or the rotator cuff can add them here.
    public var trackedMuscleGroups: Set<MuscleGroup>

    private enum CodingKeys: String, CodingKey {
        case strengthDaysPerWeek, cardioDaysPerWeek, restPreference
        case allowsTwoADays, sameDayCardioTiming, dailyStepTarget
        case excludedCoverageParts, desiredSetsPerExercise
        case trackedMuscleGroups
    }

    public static let `default` = CoachSchedulePreferences(
        strengthDaysPerWeek: 2,
        cardioDaysPerWeek: 3,
        restPreference: .defaultRolling,
        allowsTwoADays: false,
        sameDayCardioTiming: .afterStrength,
        excludedCoverageParts: [],
        desiredSetsPerExercise: 3,
        trackedMuscleGroups: MuscleGroup.defaultTracked)

    public init(strengthDaysPerWeek: Int = 2,
                cardioDaysPerWeek: Int = 3,
                restPreference: RestPreference = .defaultRolling,
                allowsTwoADays: Bool = false,
                sameDayCardioTiming: SameDayCardioTiming = .afterStrength,
                dailyStepTarget: Int = 8_000,
                excludedCoverageParts: Set<BodyPart> = [],
                desiredSetsPerExercise: Int = 3,
                trackedMuscleGroups: Set<MuscleGroup> = MuscleGroup.defaultTracked) {
        self.strengthDaysPerWeek = min(5, max(2, strengthDaysPerWeek))
        self.cardioDaysPerWeek = min(7, max(0, cardioDaysPerWeek))
        self.restPreference = restPreference
        self.allowsTwoADays = allowsTwoADays
        self.sameDayCardioTiming = sameDayCardioTiming
        self.dailyStepTarget = min(20_000, max(2_000, dailyStepTarget))
        self.excludedCoverageParts = excludedCoverageParts
        self.desiredSetsPerExercise = Self.clampDesiredSets(desiredSetsPerExercise)
        self.trackedMuscleGroups = trackedMuscleGroups.isEmpty
            ? MuscleGroup.defaultTracked : trackedMuscleGroups
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strengthDaysPerWeek = min(5, max(2, try c.decodeIfPresent(Int.self, forKey: .strengthDaysPerWeek) ?? 2))
        cardioDaysPerWeek = min(7, max(0, try c.decodeIfPresent(Int.self, forKey: .cardioDaysPerWeek) ?? 3))
        restPreference = try c.decodeIfPresent(RestPreference.self, forKey: .restPreference) ?? .defaultRolling
        allowsTwoADays = try c.decodeIfPresent(Bool.self, forKey: .allowsTwoADays) ?? false
        sameDayCardioTiming = try c.decodeIfPresent(SameDayCardioTiming.self, forKey: .sameDayCardioTiming) ?? .afterStrength
        dailyStepTarget = min(20_000, max(2_000, try c.decodeIfPresent(Int.self, forKey: .dailyStepTarget) ?? 8_000))
        excludedCoverageParts = try c.decodeIfPresent(Set<BodyPart>.self, forKey: .excludedCoverageParts) ?? []
        desiredSetsPerExercise = Self.clampDesiredSets(
            try c.decodeIfPresent(Int.self, forKey: .desiredSetsPerExercise) ?? 3
        )
        // Carry a pre-DB++ user's coverage opt-outs across: every group belonging
        // to an excluded body part drops out of the tracked set.
        if let stored = try c.decodeIfPresent(Set<MuscleGroup>.self, forKey: .trackedMuscleGroups),
           !stored.isEmpty {
            trackedMuscleGroups = stored
        } else if excludedCoverageParts.isEmpty {
            trackedMuscleGroups = MuscleGroup.defaultTracked
        } else {
            let excluded = excludedCoverageParts
            trackedMuscleGroups = MuscleGroup.defaultTracked.filter { group in
                guard let part = BodyPart.part(forGroup: group) else { return true }
                return !excluded.contains(part)
            }
        }
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

    public func withDesiredSetsPerExercise(_ sets: Int) -> CoachSchedulePreferences {
        var copy = self
        copy.desiredSetsPerExercise = Self.clampDesiredSets(sets)
        return copy
    }

    private static func clampDesiredSets(_ sets: Int) -> Int {
        min(4, max(3, sets))
    }
}
