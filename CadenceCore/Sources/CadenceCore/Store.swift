import Foundation
import SwiftData

/// Builds the shared SwiftData store. Both the iOS and watchOS apps use this,
/// so logging on the watch mirrors to the phone through the user's private
/// CloudKit database automatically (FR-9).
public enum CadenceStore {

    /// Must match the iCloud container enabled on BOTH targets in Xcode.
    public static let cloudKitContainerID = "iCloud.guru.parso.ios-workout-app"

    public static let schema = Schema([
        WorkoutSession.self,
        Exercise.self,
        SetEntry.self,
        SessionTemplate.self,
        TemplateExercise.self,
        CardioWorkout.self,
        HRSample.self,
        RouteSample.self,
        HRMDevice.self,
        Person.self
    ])

    /// - Parameters:
    ///   - inMemory: pass `true` for previews/tests (no CloudKit).
    ///   - cloudKitEnabled: when false (and not in-memory), the store runs fully
    ///     local on a single device (FR-4.5 / FR-9.4 — sync off by default).
    public static func makeModelContainer(inMemory: Bool = false,
                                          cloudKitEnabled: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if cloudKitEnabled {
            // If the compiler ever rejects `.private(_:)` on your toolchain,
            // fall back to `.automatic` — it picks up the container from the
            // app's iCloud entitlement instead.
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Deletes the on-disk default SwiftData store. Used as a dev-time recovery
    /// when a schema change makes the existing local store incompatible (e.g.
    /// the §06 `[String]` → delimited-String migration). Pre-release only; sync
    /// is off by default so there's nothing remote to lose.
    public static func destroyDefaultStore() {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: false) else { return }
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? fm.removeItem(at: support.appendingPathComponent(name))
        }
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
    public static let cloudSyncEnabled = "settings.cloudSync"// Bool
    public static let lastHealthSync = "settings.lastHealthSync" // Date (timeIntervalSince1970)
}

public enum SettingsDefault {
    public static let unit = MeasurementUnitPreference.kilograms
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
    public static let cloudSyncEnabled = false
}
