import Foundation
#if canImport(SwiftData)
import SwiftData
#endif

/// Builds the shared SwiftData stores. The shipping iPhone app uses one
/// local-only `Cladiron.store` (all models, including health-bearing rows). A
/// single store is required for SwiftData relationship integrity: the previous
/// Local/Sync split could not encode a set's Exercise relationship during save.
///
/// All stores are local-only. There is no iCloud or CloudKit access: App Review
/// Guideline 5.1.3(ii) prohibits storing personal health information in iCloud,
/// and the workout model carries heart-rate and other health data. Export/import
/// is the portable backup path. The Watch syncs through WatchConnectivity.
#if canImport(SwiftData)
public enum CadenceStore {
    /// Shared local-store compatibility marker used by iPhone and Watch.
    public static let schemaVersion = 3

    private static let sharedModelTypes: [any PersistentModel.Type] = [
        PlanningDraft.self,
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
    ]

    public static let schema = Schema(sharedModelTypes)

    /// The Watch's local-only store: the shared schema plus the phone-mirrored cardio
    /// history projection.
    public static let watchSchema = Schema(sharedModelTypes + [WatchCardioHistoryRecord.self])

    /// The H5 boundary is retained for reading and migrating pre-Cladiron.store
    /// installs. The live application store is now single, because SwiftData
    /// cannot persist a set's Exercise relationship across two store configs.
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
        PlanningDraft.self,
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

    /// The pre-split single store and the later Local/Sync pair are read only by
    /// the one-time copy into the current application store.
    public static let legacyStoreFileName = "default.store"
    public static let localStoreFileName = "Local.store"
    public static let syncStoreFileName = "Sync.store"
    public static let applicationStoreFileName = "Cladiron.store"

    /// The default SwiftData location used by the current app.
    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    public static func legacyStoreURL(
        in directory: URL = applicationSupportDirectory()
    ) -> URL { directory.appendingPathComponent(legacyStoreFileName) }

    public static func applicationStoreURL(
        in directory: URL = applicationSupportDirectory()
    ) -> URL { directory.appendingPathComponent(applicationStoreFileName) }

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

    public static func hasSplitStoreFiles(
        in directory: URL = applicationSupportDirectory(),
        fileManager: FileManager = .default
    ) -> Bool {
        let urls = splitStoreURLs(in: directory)
        return fileManager.fileExists(atPath: urls.local.path)
            && fileManager.fileExists(atPath: urls.sync.path)
    }

    public static func applicationStoreReady(
        in directory: URL = applicationSupportDirectory(),
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(atPath: directory
            .appendingPathComponent(StoreMigrationRuntime.singleStoreReadyMarkerFileName).path)
            && fileManager.fileExists(atPath: applicationStoreURL(in: directory).path)
    }

    /// Opens the single local application store. A pre-Cladiron.store legacy
    /// store or Local/Sync pair is copied into it once, before the first launch,
    /// so the store migration never strands history. The old files are left
    /// untouched as rollback copies.
    public static func makeApplicationModelContainer(
        directory: URL = applicationSupportDirectory(),
        fileManager: FileManager = .default,
        singleFactory: (URL) throws -> ModelContainer = {
            try makeSingleModelContainer(storeURL: $0)
        }
    ) throws -> ModelContainer {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let singleURL = applicationStoreURL(in: directory)
        if !applicationStoreReady(in: directory, fileManager: fileManager) {
            try StoreMigrationRuntime.migrateToSingleStore(
                directory: directory, singleURL: singleURL,
                stateURL: directory.appendingPathComponent(StoreMigrationRuntime.stateFileName),
                snapshotURL: directory.appendingPathComponent(StoreMigrationRuntime.singleStoreSnapshotFileName))
        }
        return try singleFactory(singleURL)
    }

    /// Builds the single local application store. The URL is caller-owned so
    /// tests can use a temporary store.
    public static func makeSingleModelContainer(
        storeURL: URL
    ) throws -> ModelContainer {
        let config = ModelConfiguration("app", schema: schema, url: storeURL,
                                       cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Builds the legacy two-configuration container used only to read a pre-split
    /// Local/Sync pair during migration. Both URLs are caller-owned and local-only.
    public static func makeSplitModelContainer(
        localURL: URL,
        syncURL: URL
    ) throws -> ModelContainer {
        let local = ModelConfiguration("local", schema: localSchema, url: localURL,
                                       cloudKitDatabase: .none)
        let sync = ModelConfiguration("sync", schema: syncSchema, url: syncURL,
                                      cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [local, sync])
    }

    /// - Parameters:
    ///   - inMemory: pass `true` for previews/tests.
    ///   - storeURL: an explicit local store URL for persistence tests.
    ///   - includesWatchCardioHistory: adds the Watch's local cardio projection.
    public static func makeModelContainer(inMemory: Bool = false,
                                          storeURL: URL? = nil,
                                          includesWatchCardioHistory: Bool = false) throws -> ModelContainer {
        let activeSchema = includesWatchCardioHistory ? watchSchema : schema
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: activeSchema,
                                               isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        } else if let storeURL {
            configuration = ModelConfiguration(schema: activeSchema, url: storeURL,
                                               cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: activeSchema,
                                               isStoredInMemoryOnly: false,
                                               cloudKitDatabase: .none)
        }
        return try ModelContainer(for: activeSchema, configurations: [configuration])
    }
}
#endif

// MARK: - Settings keys & defaults
//
// Stored via @AppStorage in the app layer; declared here so core math callers
// and the UI agree on keys and defaults (REQUIREMENTS §9 decisions).

public enum SettingsKey {
    public static let unit = "settings.unit"                 // MeasurementUnitPreference.rawValue
    public static let prRule = "settings.prRule"             // PRRule.rawValue
    public static let oneRepMaxFormula = "settings.formula"  // OneRepMaxFormula.rawValue
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
    public static let restSeconds = 90
    // Strength guided warm-up & cool-down (feedback batch 7 item 7 — 5 min;
    // HIIT/boxing use their protocol's own periods, not these). User-override
    // in Settings.
    public static let warmupMinutes = 5
    public static let cooldownMinutes = 5
}
