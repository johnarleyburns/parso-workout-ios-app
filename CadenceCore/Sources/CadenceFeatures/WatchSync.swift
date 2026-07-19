import Foundation
import CadenceCore

public struct WeightIncrement {
    public let chips: [Double]
    public let crownDetent: Double
    public let range: ClosedRange<Double>

    public init(unit: MeasurementUnitPreference) {
        switch unit {
        case .pounds:
            self.chips = [-5, +5]
            self.crownDetent = 2.5
            self.range = 0...650
        case .kilograms:
            self.chips = [-2.5, +2.5]
            self.crownDetent = 1.25
            self.range = 0...300
        }
    }

    public static func unitDefault() -> MeasurementUnitPreference {
        Locale.current.measurementSystem == .us ? .pounds : .kilograms
    }
}

public enum WatchSync {
    public enum Key {
        public static let command = "command"
        public static let requestSettingsSync = "request_settings_sync"
        public static let contextUpdatedAt = "watchSync.contextUpdatedAt"

        public static let unit = "settings.unit"
        public static let intervalColorBlind = "settings.intervalColorBlind"
        public static let restSeconds = "settings.restSeconds"
        public static let warmupMinutes = "settings.warmupMinutes"
        public static let cooldownMinutes = "settings.cooldownMinutes"
        public static let workoutSounds = "settings.workoutSounds"
        public static let recentPartners = "partners.recent"
    }

    public enum Status: Equatable, Sendable {
        case idle
        case syncing(Date)
        case synced(Date)
        case failed(String, Date?)

        public var isInProgress: Bool {
            if case .syncing = self { return true }
            return false
        }

        public var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }

        public var toastText: String? {
            switch self {
            case .idle: return nil
            case .syncing: return "Syncing to Watch"
            case .synced: return "Watch synced"
            case .failed(let message, _):
                return message.isEmpty ? "Watch sync failed" : "Watch sync failed: \(message)"
            }
        }

        public func settingsText(lastSyncAt: Date?) -> String {
            switch self {
            case .syncing:
                return "Syncing..."
            case .synced(let date):
                return "Synced \(Self.relativeText(for: date))"
            case .failed(let message, _):
                return message.isEmpty ? "Failed" : message
            case .idle:
                guard let lastSyncAt else { return "Never synced" }
                return "Synced \(Self.relativeText(for: lastSyncAt))"
            }
        }

        public static func lastSyncText(_ date: Date?) -> String {
            guard let date else { return "Never" }
            return date.formatted(date: .abbreviated, time: .shortened)
        }

        private static func relativeText(for date: Date, now: Date = Date()) -> String {
            let seconds = max(0, Int(now.timeIntervalSince(date)))
            if seconds < 5 { return "just now" }
            if seconds < 60 { return "\(seconds)s ago" }
            let minutes = seconds / 60
            if minutes < 60 { return "\(minutes)m ago" }
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    public struct Preferences: Equatable, Sendable {
        public var unit: MeasurementUnitPreference
        public var intervalColorBlind: Bool
        public var restSeconds: Int
        public var warmupMinutes: Int
        public var cooldownMinutes: Int
        public var workoutSounds: Bool
        public var recentPartnerNames: [String]

        public init(unit: MeasurementUnitPreference = .kilograms,
                    intervalColorBlind: Bool = false,
                    restSeconds: Int = 90,
                    warmupMinutes: Int = 5,
                    cooldownMinutes: Int = 5,
                    workoutSounds: Bool = true,
                    recentPartnerNames: [String] = []) {
            self.unit = unit
            self.intervalColorBlind = intervalColorBlind
            self.restSeconds = restSeconds
            self.warmupMinutes = warmupMinutes
            self.cooldownMinutes = cooldownMinutes
            self.workoutSounds = workoutSounds
            self.recentPartnerNames = recentPartnerNames
        }

        public static func contextDict(_ prefs: Preferences) -> [String: Any] {
            var dict: [String: Any] = [
                Key.unit: prefs.unit.rawValue,
                Key.intervalColorBlind: prefs.intervalColorBlind,
                Key.restSeconds: prefs.restSeconds,
                Key.warmupMinutes: prefs.warmupMinutes,
                Key.cooldownMinutes: prefs.cooldownMinutes,
                Key.workoutSounds: prefs.workoutSounds,
            ]
            if !prefs.recentPartnerNames.isEmpty {
                dict[Key.recentPartners] = prefs.recentPartnerNames
            }
            return dict
        }

        public static func contextDict(_ prefs: Preferences, updatedAt: Date) -> [String: Any] {
            var dict = contextDict(prefs)
            dict[Key.contextUpdatedAt] = updatedAt
            return dict
        }

        public func applying(context: [String: Any]) -> Preferences {
            var copy = self
            if let raw = context[Key.unit] as? String,
               let u = MeasurementUnitPreference(rawValue: raw) {
                copy.unit = u
            }
            if let cb = context[Key.intervalColorBlind] as? Bool {
                copy.intervalColorBlind = cb
            }
            if let rs = context[Key.restSeconds] as? Int {
                copy.restSeconds = rs
            }
            if let wm = context[Key.warmupMinutes] as? Int {
                copy.warmupMinutes = wm
            }
            if let cm = context[Key.cooldownMinutes] as? Int {
                copy.cooldownMinutes = cm
            }
            if let sounds = context[Key.workoutSounds] as? Bool {
                copy.workoutSounds = sounds
            }
            if let names = context[Key.recentPartners] as? [String] {
                copy.recentPartnerNames = names
            }
            return copy
        }
    }

    public static func requestSettingsSyncMessage() -> [String: Any] {
        [Key.command: Key.requestSettingsSync]
    }
}
