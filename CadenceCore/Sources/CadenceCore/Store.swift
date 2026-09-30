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
        PersistedClientRelationship.self,
        ExerciseSuggestionExclusion.self,
        ScheduledWorkout.self
    ])

    /// The H5 boundary. Health-bearing rows remain in an on-device
    /// configuration; library, roster, plans, and schedule rows are the only
    /// rows eligible for the new CloudKit container. The two schemas are kept
    /// explicit so a new @Model cannot silently cross the privacy boundary.
    public static let localSchema = Schema([
        WorkoutSession.self,
        SetEntry.self,
        CardioWorkout.self,
        ReadinessEntry.self,
        HRSample.self,
        RouteSample.self,
        Assessment.self
    ])

    public static let syncSchema = Schema([
        Exercise.self,
        SessionTemplate.self,
        TemplateExercise.self,
        HRMDevice.self,
        Person.self,
        PersistedPlan.self,
        PersistedPlanHeader.self,
        PersistedPlanWeek.self,
        PersistedPlanDay.self,
        PersistedPlanSession.self,
        PersistedPlanItem.self,
        PersistedPlanSet.self,
        PersistedClientRelationship.self,
        ExerciseSuggestionExclusion.self,
        ScheduledWorkout.self
    ])

    public static let splitCloudKitContainerID = "iCloud.guru.parso.cladiron.sync"

    public static let legacyStoreFileName = "default.store"
    public static let localStoreFileName = "Local.store"
    public static let syncStoreFileName = "Sync.store"

    /// The default SwiftData location used by the legacy single-store app.
    /// Keeping this explicit lets H5 inspect it without opening or deleting an
    /// unknown path.
    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    public static func legacyStoreURL(
        in directory: URL = applicationSupportDirectory()
    ) -> URL { directory.appendingPathComponent(legacyStoreFileName) }

    public static func splitStoreURLs(
        in directory: URL = applicationSupportDirectory()
    ) -> (local: URL, sync: URL) {
        (directory.appendingPathComponent(localStoreFileName),
         directory.appendingPathComponent(syncStoreFileName))
    }

    public static func splitStoreReady(
        in directory: URL = applicationSupportDirectory(),
        fileManager: FileManager = .default
    ) -> Bool {
        let urls = splitStoreURLs(in: directory)
        return fileManager.fileExists(atPath: directory
            .appendingPathComponent(StoreMigrationRuntime.readyMarkerFileName).path)
            && fileManager.fileExists(atPath: urls.local.path)
            && fileManager.fileExists(atPath: urls.sync.path)
    }

    /// Uses the split container for new installs and completed H5 migrations;
    /// existing legacy installs remain on their original container until the
    /// user explicitly completes the migration in Backup & Restore.
    public static func makeApplicationModelContainer(
        cloudKitEnabled: Bool = true,
        directory: URL = applicationSupportDirectory(),
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        let legacy = legacyStoreURL(in: directory)
        let urls = splitStoreURLs(in: directory)
        let hasLegacy = fileManager.fileExists(atPath: legacy.path)
        if splitStoreReady(in: directory, fileManager: fileManager) || !hasLegacy {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return try makeSplitModelContainer(localURL: urls.local, syncURL: urls.sync,
                                                cloudKitEnabled: cloudKitEnabled)
        }
        return try makeModelContainer(inMemory: false, cloudKitEnabled: cloudKitEnabled)
    }

    public static func activeCloudKitContainerID(
        directory: URL = applicationSupportDirectory(),
        fileManager: FileManager = .default
    ) -> String {
        let legacy = legacyStoreURL(in: directory)
        return splitStoreReady(in: directory, fileManager: fileManager)
            || !fileManager.fileExists(atPath: legacy.path)
            ? splitCloudKitContainerID : cloudKitContainerID
    }

    /// Builds the two-configuration container used by H5 migration and new
    /// installs after the production schema is deployed. Both URLs are
    /// caller-owned so tests can use temporary local-only stores and the app
    /// can retain an old store for the rollback window.
    public static func makeSplitModelContainer(
        localURL: URL,
        syncURL: URL,
        cloudKitEnabled: Bool = true
    ) throws -> ModelContainer {
        let local = ModelConfiguration("local", schema: localSchema, url: localURL,
                                       cloudKitDatabase: .none)
        let syncDatabase: ModelConfiguration.CloudKitDatabase = cloudKitEnabled
            ? .private(splitCloudKitContainerID)
            : .none
        let sync = ModelConfiguration("sync", schema: syncSchema, url: syncURL,
                                      cloudKitDatabase: syncDatabase)
        return try ModelContainer(for: schema, configurations: [local, sync])
    }

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
