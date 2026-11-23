import Foundation
#if canImport(SwiftData)
import SwiftData
#endif

/// Builds the shared SwiftData stores. The iPhone keeps health-bearing rows in
/// an on-device `Local.store` and mirrors the library, roster, and plan slice to
/// the user's **private** CloudKit database
/// (`iCloud.guru.parso.cladiron.sync`). The watch uses a local-only store and
/// syncs through WatchConnectivity so the phone is the sole CloudKit writer.
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
    /// history projection. Never used for the phone or its CloudKit configurations.
    public static let watchSchema = Schema(sharedModelTypes + [WatchCardioHistoryRecord.self])

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

    public static let splitCloudKitContainerID = "iCloud.guru.parso.cladiron.sync"

    /// The pre-split single store. It is read exactly once, by the automatic
    /// upgrade copy, and is never opened as an application store again.
    public static let legacyStoreFileName = "default.store"
    public static let localStoreFileName = "Local.store"
    public static let syncStoreFileName = "Sync.store"

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

    /// Opens the split container used by every current install. A pre-split
    /// single store is copied into `Local.store`/`Sync.store` once, before the
    /// first split launch, so retiring the legacy fallback never strands an
    /// upgraded install. The copy is verified and the old file is left in place
    /// untouched as the rollback copy.
    public static func makeApplicationModelContainer(
        cloudKitEnabled: Bool = true,
        directory: URL = applicationSupportDirectory(),
        fileManager: FileManager = .default,
        splitFactory: (URL, URL, Bool) throws -> ModelContainer = {
            try makeSplitModelContainer(localURL: $0, syncURL: $1, cloudKitEnabled: $2)
        }
    ) throws -> ModelContainer {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = legacyStoreURL(in: directory)
        let urls = splitStoreURLs(in: directory)
        if fileManager.fileExists(atPath: legacy.path),
           !splitStoreReady(in: directory, fileManager: fileManager) {
            try StoreMigrationRuntime.migrateLegacyStoreAtLaunch(
                legacyURL: legacy, localURL: urls.local, syncURL: urls.sync,
                stateURL: directory.appendingPathComponent(StoreMigrationRuntime.stateFileName),
                snapshotURL: directory.appendingPathComponent(StoreMigrationRuntime.snapshotFileName))
        }
        do {
            return try splitFactory(urls.local, urls.sync, cloudKitEnabled)
        } catch where cloudKitEnabled {
            // A CloudKit mirroring setup failure (account, entitlement, or
            // schema state) must not crash launch. Open the same on-disk
            // stores local-only: no data is deleted or replaced, and
            // mirroring resumes once CloudKit is usable again.
            return try splitFactory(urls.local, urls.sync, false)
        }
    }

    /// Builds the two-configuration container used by every current install.
    /// Both URLs are caller-owned so tests can use temporary local-only stores.
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
                                          storeURL: URL? = nil,
                                          includesWatchCardioHistory: Bool = false) throws -> ModelContainer {
        // Only the Watch asks for the phone-mirrored cardio projection, and it is local-only.
        let activeSchema = includesWatchCardioHistory && !cloudKitEnabled ? watchSchema : schema
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: activeSchema, isStoredInMemoryOnly: inMemory)
        } else if let storeURL {
            // Explicit URLs are used by persistence regression tests and by the
            // isolated UI-test store. They are always local-only: a test must
            // never touch the user's CloudKit database.
            configuration = ModelConfiguration(schema: activeSchema, url: storeURL,
                                               cloudKitDatabase: .none)
        } else if !cloudKitEnabled {
            configuration = ModelConfiguration(schema: activeSchema, isStoredInMemoryOnly: false)
        } else {
            configuration = ModelConfiguration(schema: activeSchema, isStoredInMemoryOnly: false,
                                               cloudKitDatabase: .private(splitCloudKitContainerID))
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
