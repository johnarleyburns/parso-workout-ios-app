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
        // In UI-test mode, start from a clean, deterministic preference set so
        // test order can never bleed through persisted UserDefaults.
        if ProcessInfo.processInfo.arguments.contains("-uiTest") {
            for key in [SettingsKey.unit, SettingsKey.prRule, SettingsKey.oneRepMaxFormula,
                        SettingsKey.stepGoal, SettingsKey.weeklyCardioMinutesGoal,
                        SettingsKey.restSeconds, SettingsKey.warmupMinutes, SettingsKey.cooldownMinutes,
                        SettingsKey.lastHealthSync, "settings.autoRest",
                        "settings.idleTimeout", "settings.gpsHighAccuracy", "settings.autoPause",
                        "settings.intervalColorBlind", "settings.spokenCues", "settings.plateRounding",
                        "settings.preWorkoutCountdown", "settings.autoSaveHealth",
                        "settings.autoEndOnIdle", "settings.workoutSounds",
                        "settings.trainingGoal", "settings.experienceLevel",
                        "settings.useHRMonitoring",
                        "settings.coachPreferenceProfile",
                        "settings.coachSchedulePreferences"] {
                defaults.removeObject(forKey: key)
            }
        }
        // Onboarding — true after the user completes the 4-screen flow.
        self.hasCompletedOnboarding = defaults.bool(forKey: "settings.hasCompletedOnboarding")
        self.unit = Self.read(defaults, SettingsKey.unit, MeasurementUnitPreference.self) ?? SettingsDefault.unit
        self.prRule = Self.read(defaults, SettingsKey.prRule, PRRule.self) ?? SettingsDefault.prRule
        self.formula = Self.read(defaults, SettingsKey.oneRepMaxFormula, OneRepMaxFormula.self) ?? SettingsDefault.oneRepMaxFormula
        self.stepGoal = defaults.object(forKey: SettingsKey.stepGoal) as? Int ?? SettingsDefault.stepGoal
        self.weeklyCardioMinutesGoal = defaults.object(forKey: SettingsKey.weeklyCardioMinutesGoal) as? Int ?? SettingsDefault.weeklyCardioMinutesGoal
        self.restSeconds = defaults.object(forKey: SettingsKey.restSeconds) as? Int ?? SettingsDefault.restSeconds
        self.warmupMinutes = defaults.object(forKey: SettingsKey.warmupMinutes) as? Int ?? SettingsDefault.warmupMinutes
        self.cooldownMinutes = defaults.object(forKey: SettingsKey.cooldownMinutes) as? Int ?? SettingsDefault.cooldownMinutes
        self.autoStartRest = defaults.object(forKey: "settings.autoRest") as? Bool ?? true
        // Field-testing §06 polish settings.
        self.idleTimeoutMinutes = defaults.object(forKey: "settings.idleTimeout") as? Int ?? 10
        self.gpsHighAccuracy = defaults.object(forKey: "settings.gpsHighAccuracy") as? Bool ?? false
        self.autoPause = defaults.object(forKey: "settings.autoPause") as? Bool ?? false
        self.intervalColorBlind = defaults.object(forKey: "settings.intervalColorBlind") as? Bool ?? false
        self.spokenCues = defaults.object(forKey: "settings.spokenCues") as? Bool ?? false
        self.plateRounding = defaults.object(forKey: "settings.plateRounding") as? Bool ?? false
        // Finished workouts write a summary to Apple Health automatically (P1 #8);
        // can be turned off in Settings.
        self.autoSaveHealth = defaults.object(forKey: "settings.autoSaveHealth") as? Bool ?? true
        // Strength idle watchdog is opt-out (batch 7 item 8); transition bells opt-out
        // (batch 7 item 9). Both default on = prior behavior.
        self.autoEndOnIdle = defaults.object(forKey: "settings.autoEndOnIdle") as? Bool ?? true
        self.workoutSounds = defaults.object(forKey: "settings.workoutSounds") as? Bool ?? true
        self.preWorkoutCountdown = defaults.object(forKey: "settings.preWorkoutCountdown") as? Int ?? 10
        // Coach engine inputs (strength-pivot P3, D4): personalize insights. Full
        // goal/experience onboarding intake comes in P7; sensible defaults until then.
        self.trainingGoal = Self.read(defaults, "settings.trainingGoal", TrainingGoal.self) ?? .hypertrophy
        self.experienceLevel = Self.read(defaults, "settings.experienceLevel", ExperienceLevel.self) ?? .intermediate
        self.useHRMonitoring = defaults.object(forKey: "settings.useHRMonitoring") as? Bool ?? false
        self.recoveryAwareCoachV2 = defaults.object(forKey: "settings.recoveryAwareCoachV2") as? Bool ?? true
        self.lastCoachComputeDay = defaults.string(forKey: "settings.lastCoachComputeDay") ?? ""
        self.favoriteRoutineIDs = Set(defaults.stringArray(forKey: "settings.favoriteRoutineIDs") ?? [])
        // In UI tests the countdown is off by default (so workout-start flows stay
        // fast); a test can opt in with `-preCountdown N`.
        if ProcessInfo.processInfo.arguments.contains("-uiTest") {
            let a = ProcessInfo.processInfo.arguments
            // Onboarding is skipped by default in UI tests so existing tests land
            // on Home. Pass `-showOnboarding` to opt into the flow.
            if a.contains("-showOnboarding") {
                self.hasCompletedOnboarding = false
            } else {
                self.hasCompletedOnboarding = true
            }
            if let i = a.firstIndex(of: "-preCountdown"), i + 1 < a.count, let n = Int(a[i + 1]) {
                self.preWorkoutCountdown = n
            } else {
                self.preWorkoutCountdown = 0
            }
            // The guided warm-up is also off by default in UI tests so editor-start
            // flows land on the session fast; opt in with `-warmupMinutes N`.
            if let i = a.firstIndex(of: "-warmupMinutes"), i + 1 < a.count, let n = Int(a[i + 1]) {
                self.warmupMinutes = n
            } else {
                self.warmupMinutes = 0
            }
            if a.contains("-enableHRMonitoring") {
                self.useHRMonitoring = true
            }
        }
    }

    var unit: MeasurementUnitPreference { didSet { defaults.set(unit.rawValue, forKey: SettingsKey.unit) } }
    var prRule: PRRule { didSet { defaults.set(prRule.rawValue, forKey: SettingsKey.prRule) } }
    var formula: OneRepMaxFormula { didSet { defaults.set(formula.rawValue, forKey: SettingsKey.oneRepMaxFormula) } }
    var stepGoal: Int { didSet { defaults.set(stepGoal, forKey: SettingsKey.stepGoal) } }
    /// Weekly cardio-minutes goal shown on the Home cardio tile (feedback batch 4).
    var weeklyCardioMinutesGoal: Int { didSet { defaults.set(weeklyCardioMinutesGoal, forKey: SettingsKey.weeklyCardioMinutesGoal) } }
    var restSeconds: Int { didSet { defaults.set(restSeconds, forKey: SettingsKey.restSeconds) } }
    /// Warm-up / cool-down countdown length for strength workouts (minutes).
    var warmupMinutes: Int { didSet { defaults.set(warmupMinutes, forKey: SettingsKey.warmupMinutes) } }
    var cooldownMinutes: Int { didSet { defaults.set(cooldownMinutes, forKey: SettingsKey.cooldownMinutes) } }
    var autoStartRest: Bool { didSet { defaults.set(autoStartRest, forKey: "settings.autoRest") } }
    // Field-testing §06 polish settings.
    var idleTimeoutMinutes: Int { didSet { defaults.set(idleTimeoutMinutes, forKey: "settings.idleTimeout") } }
    var gpsHighAccuracy: Bool { didSet { defaults.set(gpsHighAccuracy, forKey: "settings.gpsHighAccuracy") } }
    var autoPause: Bool { didSet { defaults.set(autoPause, forKey: "settings.autoPause") } }
    var intervalColorBlind: Bool { didSet { defaults.set(intervalColorBlind, forKey: "settings.intervalColorBlind") } }
    var spokenCues: Bool { didSet { defaults.set(spokenCues, forKey: "settings.spokenCues") } }
    var plateRounding: Bool { didSet { defaults.set(plateRounding, forKey: "settings.plateRounding") } }
    /// Write a workout summary to Apple Health automatically when a workout ends.
    var autoSaveHealth: Bool { didSet { defaults.set(autoSaveHealth, forKey: "settings.autoSaveHealth") } }
    /// Auto-end a strength workout after the idle timeout (batch 7 item 8; opt-out).
    var autoEndOnIdle: Bool { didSet { defaults.set(autoEndOnIdle, forKey: "settings.autoEndOnIdle") } }
    /// Play a bell at workout/phase transitions (batch 7 item 9; opt-out).
    var workoutSounds: Bool { didSet { defaults.set(workoutSounds, forKey: "settings.workoutSounds") } }
    /// Get-ready countdown before a workout starts (seconds; 0 disables).
    var preWorkoutCountdown: Int { didSet { defaults.set(preWorkoutCountdown, forKey: "settings.preWorkoutCountdown") } }
    /// Primary training goal driving the Coach engine's insights (P3, D4).
    var trainingGoal: TrainingGoal { didSet { defaults.set(trainingGoal.rawValue, forKey: "settings.trainingGoal") } }
    /// Training experience, scaling the engine's volume landmarks (P3).
    var experienceLevel: ExperienceLevel { didSet { defaults.set(experienceLevel.rawValue, forKey: "settings.experienceLevel") } }
    var useHRMonitoring: Bool { didSet { defaults.set(useHRMonitoring, forKey: "settings.useHRMonitoring") } }
    /// Recovery-aware Coach v2: new eligibility-gated decision engine. Enable by default
    /// in debug builds; can be toggled in Settings for rollback testing.
    var recoveryAwareCoachV2: Bool { didSet { defaults.set(recoveryAwareCoachV2, forKey: "settings.recoveryAwareCoachV2") } }
    var lastCoachComputeDay: String { didSet { defaults.set(lastCoachComputeDay, forKey: "settings.lastCoachComputeDay") } }
    /// Whether the user has completed the new-user onboarding flow.
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: "settings.hasCompletedOnboarding") } }
    var favoriteRoutineIDs: Set<String> { didSet { defaults.set(Array(favoriteRoutineIDs), forKey: "settings.favoriteRoutineIDs") } }

    /// Learned Coach preferences from alternative selections. Stored as JSON in
    /// UserDefaults because it is compact and gets exported transparently.
    var coachPreferenceProfile: CoachPreferenceProfile {
        get {
            guard let data = defaults.data(forKey: "settings.coachPreferenceProfile"),
                  let profile = try? JSONDecoder().decode(CoachPreferenceProfile.self, from: data)
            else { return .empty }
            return profile
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "settings.coachPreferenceProfile")
            }
        }
    }

    /// User-selected weekly schedule preferences, replacing hard-coded defaults.
    /// Persisted as JSON in UserDefaults; defaults conservatively.
    var coachSchedulePreferences: CoachSchedulePreferences {
        get {
            guard let data = defaults.data(forKey: "settings.coachSchedulePreferences"),
                  let prefs = try? JSONDecoder().decode(CoachSchedulePreferences.self, from: data)
            else { return .default }
            return prefs
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "settings.coachSchedulePreferences")
            }
        }
    }

    @discardableResult
    func recordCoachSelection(_ session: CoachSession, alternatives: [CoachSession],
                               at date: Date = Date()) -> CoachPreferenceProfile {
        var profile = coachPreferenceProfile
        profile.recordSelection(session, from: alternatives, at: date)
        coachPreferenceProfile = profile
        return profile
    }

    func isRoutineFavorite(_ id: String) -> Bool { favoriteRoutineIDs.contains(id) }
    func toggleFavoriteRoutine(_ id: String) {
        if favoriteRoutineIDs.contains(id) { favoriteRoutineIDs.remove(id) }
        else { favoriteRoutineIDs.insert(id) }
    }

    private static func read<T: RawRepresentable>(_ d: UserDefaults, _ key: String, _ type: T.Type) -> T? where T.RawValue == String {
        guard let raw = d.string(forKey: key) else { return nil }
        return T(rawValue: raw)
    }
}

// MARK: - Lossless preferences export/import (FR-6.2)

extension AppSettings {
    /// A complete snapshot of all preferences (settings + schedule + learned coach
    /// profile) so a fresh install round-trips exactly.
    func exportPreferences() -> ExportPreferences {
        ExportPreferences(
            unit: unit.rawValue, prRule: prRule.rawValue, oneRepMaxFormula: formula.rawValue,
            stepGoal: nil, weeklyCardioMinutesGoal: weeklyCardioMinutesGoal, restSeconds: restSeconds,
            warmupMinutes: warmupMinutes, cooldownMinutes: cooldownMinutes, autoStartRest: autoStartRest,
            idleTimeoutMinutes: idleTimeoutMinutes, gpsHighAccuracy: gpsHighAccuracy, autoPause: autoPause,
            intervalColorBlind: intervalColorBlind, spokenCues: spokenCues, plateRounding: plateRounding,
            autoSaveHealth: autoSaveHealth, autoEndOnIdle: autoEndOnIdle, workoutSounds: workoutSounds,
            preWorkoutCountdown: preWorkoutCountdown, trainingGoal: trainingGoal.rawValue,
            experienceLevel: experienceLevel.rawValue, useHRMonitoring: useHRMonitoring,
            recoveryAwareCoachV2: recoveryAwareCoachV2, favoriteRoutineIDs: Array(favoriteRoutineIDs),
            hasCompletedOnboarding: hasCompletedOnboarding,
            schedulePreferences: coachSchedulePreferences, coachProfile: coachPreferenceProfile)
    }

    /// Restores preferences from an imported export. Only non-nil fields are applied
    /// (partial/legacy exports never clobber existing settings).
    func applyImportedPreferences(_ p: ExportPreferences) {
        if let v = p.unit.flatMap(MeasurementUnitPreference.init(rawValue:)) { unit = v }
        if let v = p.prRule.flatMap(PRRule.init(rawValue:)) { prRule = v }
        if let v = p.oneRepMaxFormula.flatMap(OneRepMaxFormula.init(rawValue:)) { formula = v }
        if let v = p.stepGoal { stepGoal = v }
        if let v = p.weeklyCardioMinutesGoal { weeklyCardioMinutesGoal = v }
        if let v = p.restSeconds { restSeconds = v }
        if let v = p.warmupMinutes { warmupMinutes = v }
        if let v = p.cooldownMinutes { cooldownMinutes = v }
        if let v = p.autoStartRest { autoStartRest = v }
        if let v = p.idleTimeoutMinutes { idleTimeoutMinutes = v }
        if let v = p.gpsHighAccuracy { gpsHighAccuracy = v }
        if let v = p.autoPause { autoPause = v }
        if let v = p.intervalColorBlind { intervalColorBlind = v }
        if let v = p.spokenCues { spokenCues = v }
        if let v = p.plateRounding { plateRounding = v }
        if let v = p.autoSaveHealth { autoSaveHealth = v }
        if let v = p.autoEndOnIdle { autoEndOnIdle = v }
        if let v = p.workoutSounds { workoutSounds = v }
        if let v = p.preWorkoutCountdown { preWorkoutCountdown = v }
        if let v = p.trainingGoal.flatMap(TrainingGoal.init(rawValue:)) { trainingGoal = v }
        if let v = p.experienceLevel.flatMap(ExperienceLevel.init(rawValue:)) { experienceLevel = v }
        if let v = p.useHRMonitoring { useHRMonitoring = v }
        if let v = p.recoveryAwareCoachV2 { recoveryAwareCoachV2 = v }
        if let v = p.favoriteRoutineIDs { favoriteRoutineIDs = Set(v) }
        if let v = p.hasCompletedOnboarding { hasCompletedOnboarding = v }
        if let v = p.schedulePreferences { coachSchedulePreferences = v }
        if let v = p.coachProfile { coachPreferenceProfile = v }
    }
}
