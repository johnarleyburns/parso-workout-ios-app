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
    public struct Preferences: Equatable, Sendable {
        public var unit: MeasurementUnitPreference
        public var intervalColorBlind: Bool
        public var restSeconds: Int
        public var cooldownMinutes: Int
        public var recentPartnerNames: [String]

        public init(unit: MeasurementUnitPreference = .kilograms,
                    intervalColorBlind: Bool = false,
                    restSeconds: Int = 90,
                    cooldownMinutes: Int = 5,
                    recentPartnerNames: [String] = []) {
            self.unit = unit
            self.intervalColorBlind = intervalColorBlind
            self.restSeconds = restSeconds
            self.cooldownMinutes = cooldownMinutes
            self.recentPartnerNames = recentPartnerNames
        }

        public static func contextDict(_ prefs: Preferences) -> [String: Any] {
            var dict: [String: Any] = [
                "settings.unit": prefs.unit.rawValue,
                "settings.intervalColorBlind": prefs.intervalColorBlind,
                "settings.restSeconds": prefs.restSeconds,
                "settings.cooldownMinutes": prefs.cooldownMinutes,
            ]
            if !prefs.recentPartnerNames.isEmpty {
                dict["partners.recent"] = prefs.recentPartnerNames
            }
            return dict
        }

        public func applying(context: [String: Any]) -> Preferences {
            var copy = self
            if let raw = context["settings.unit"] as? String,
               let u = MeasurementUnitPreference(rawValue: raw) {
                copy.unit = u
            }
            if let cb = context["settings.intervalColorBlind"] as? Bool {
                copy.intervalColorBlind = cb
            }
            if let rs = context["settings.restSeconds"] as? Int {
                copy.restSeconds = rs
            }
            if let cm = context["settings.cooldownMinutes"] as? Int {
                copy.cooldownMinutes = cm
            }
            if let names = context["partners.recent"] as? [String] {
                copy.recentPartnerNames = names
            }
            return copy
        }
    }
}
