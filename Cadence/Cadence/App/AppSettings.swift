import Foundation
import SwiftUI
import Observation
import CadenceCore

/// User preferences (REQUIREMENTS §9 decisions), persisted in UserDefaults and
/// observable for SwiftUI. Resolves the open questions with sensible defaults:
/// PR = best estimated 1RM, Epley formula, kg, 10k step goal, 90s rest, sync off.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.unit = Self.read(defaults, SettingsKey.unit, MeasurementUnitPreference.self) ?? SettingsDefault.unit
        self.prRule = Self.read(defaults, SettingsKey.prRule, PRRule.self) ?? SettingsDefault.prRule
        self.formula = Self.read(defaults, SettingsKey.oneRepMaxFormula, OneRepMaxFormula.self) ?? SettingsDefault.oneRepMaxFormula
        self.stepGoal = defaults.object(forKey: SettingsKey.stepGoal) as? Int ?? SettingsDefault.stepGoal
        self.restSeconds = defaults.object(forKey: SettingsKey.restSeconds) as? Int ?? SettingsDefault.restSeconds
        self.autoStartRest = defaults.object(forKey: "settings.autoRest") as? Bool ?? true
        self.cloudSyncEnabled = defaults.object(forKey: SettingsKey.cloudSyncEnabled) as? Bool ?? SettingsDefault.cloudSyncEnabled
    }

    var unit: MeasurementUnitPreference { didSet { defaults.set(unit.rawValue, forKey: SettingsKey.unit) } }
    var prRule: PRRule { didSet { defaults.set(prRule.rawValue, forKey: SettingsKey.prRule) } }
    var formula: OneRepMaxFormula { didSet { defaults.set(formula.rawValue, forKey: SettingsKey.oneRepMaxFormula) } }
    var stepGoal: Int { didSet { defaults.set(stepGoal, forKey: SettingsKey.stepGoal) } }
    var restSeconds: Int { didSet { defaults.set(restSeconds, forKey: SettingsKey.restSeconds) } }
    var autoStartRest: Bool { didSet { defaults.set(autoStartRest, forKey: "settings.autoRest") } }
    var cloudSyncEnabled: Bool { didSet { defaults.set(cloudSyncEnabled, forKey: SettingsKey.cloudSyncEnabled) } }

    private static func read<T: RawRepresentable>(_ d: UserDefaults, _ key: String, _ type: T.Type) -> T? where T.RawValue == String {
        guard let raw = d.string(forKey: key) else { return nil }
        return T(rawValue: raw)
    }
}
