import Foundation
import SwiftData

/// Builds the shared SwiftData store. The iPhone mirrors the store to the user's
/// **private** CloudKit database (`iCloud.guru.parso.ios-workout-app`). The watch
/// uses a local-only store and syncs through WatchConnectivity so the phone is
/// the sole CloudKit writer.
public enum CadenceStore {
    /// Shared local-store compatibility marker used by iPhone and Watch.
    public static let schemaVersion = 3

    /// The private CloudKit container backing the iPhone SwiftData store. Must
    /// match the `com.apple.developer.icloud-container-identifiers` entitlement
    /// on the iOS target.
    public static let cloudKitContainerID = "iCloud.guru.parso.ios-workout-app"

    public static let schema = Schema([
        WorkoutSession.self,
        Exercise.self,
        SetEntry.self,
        SessionTemplate.self,
        TemplateExercise.self,
        CardioWorkout.self,
        ReadinessEntry.self,
        HRSample.self,
        RouteSample.self,
        HRMDevice.self,
        Person.self,
        Assessment.self,
        PersistedPlan.self,
        PersistedPlanHeader.self,
        PersistedPlanWeek.self,
        PersistedPlanDay.self,
        PersistedPlanSession.self,
        PersistedPlanItem.self,
        PersistedPlanSet.self,
        PersistedClientRelationship.self
    ])

    /// - Parameters:
    ///   - inMemory: pass `true` for previews/tests — that store never touches CloudKit.
    ///   - cloudKitEnabled: pass `false` for the watch app; the phone remains the
    ///     sole CloudKit writer and watch data moves over WatchConnectivity.
    public static func makeModelContainer(inMemory: Bool = false,
                                          cloudKitEnabled: Bool = true,
                                          storeURL: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        } else if let storeURL {
            // Explicit URLs are used by persistence regression tests and by the
            // isolated UI-test store. They are always local-only: a test must
            // never touch the user's CloudKit database.
            configuration = ModelConfiguration(schema: schema, url: storeURL,
                                               cloudKitDatabase: .none)
        } else if !cloudKitEnabled {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false,
                                               cloudKitDatabase: .private(cloudKitContainerID))
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

}

// MARK: - Settings keys & defaults
//
// Stored via @AppStorage in the app layer; declared here so core math callers
// and the UI agree on keys and defaults (REQUIREMENTS §9 decisions).

public enum SettingsKey {
    public static let unit = "settings.unit"                 // MeasurementUnitPreference.rawValue
    public static let prRule = "settings.prRule"             // PRRule.rawValue
    public static let oneRepMaxFormula = "settings.formula"  // OneRepMaxFormula.rawValue
    public static let stepGoal = "settings.stepGoal"         // Int
    public static let weeklyCardioMinutesGoal = "settings.cardioGoal" // Int (minutes/week)
    public static let restSeconds = "settings.restSeconds"   // Int
    public static let warmupMinutes = "settings.warmupMinutes"   // Int (minutes)
    public static let cooldownMinutes = "settings.cooldownMinutes" // Int (minutes)
    public static let distanceUnit = "settings.distanceUnit"     // DistanceUnitPreference.rawValue
    public static let lastHealthSync = "settings.lastHealthSync" // Date (timeIntervalSince1970)
}

public enum SettingsDefault {
    public static let unit = MeasurementUnitPreference.kilograms
    public static let distanceUnit = DistanceUnitPreference.kilometers
    public static let prRule = PRRule.estimated1RM
    public static let oneRepMaxFormula = OneRepMaxFormula.epley
    public static let stepGoal = 10_000
    public static let weeklyCardioMinutesGoal = 250
    public static let restSeconds = 90
    // Strength guided warm-up & cool-down (feedback batch 7 item 7 — 5 min;
    // HIIT/boxing use their protocol's own periods, not these). User-override
    // in Settings.
    public static let warmupMinutes = 5
    public static let cooldownMinutes = 5
}
