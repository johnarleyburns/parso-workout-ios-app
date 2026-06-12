import SwiftUI
import SwiftData
import CadenceCore

@main
struct CadenceApp: App {
    @State private var model = AppModel()
    @State private var settings = AppSettings()
    @State private var active = ActiveWorkoutModel()
    let container: ModelContainer

    /// Bump when an incompatible on-disk schema change ships, so the local
    /// store is reset once on first launch of the new build. The §06
    /// `[String]` → delimited-String change is version 2: an old store still
    /// has `Array<String>` columns that log "Could not materialize" faults when
    /// SwiftData migrates them, so we discard it rather than migrate.
    private static let schemaVersion = 2
    private static let schemaVersionKey = "cadence.localSchemaVersion"

    init() {
        let args = ProcessInfo.processInfo.arguments
        let uiTest = args.contains("-uiTest")
        let cloud = !uiTest && (UserDefaults.standard.object(forKey: SettingsKey.cloudSyncEnabled) as? Bool ?? false)

        // Reset a pre-version-2 local store once (pre-release; sync off by
        // default so there's nothing remote to lose).
        if !uiTest, UserDefaults.standard.integer(forKey: Self.schemaVersionKey) < Self.schemaVersion {
            CadenceStore.destroyDefaultStore()
            UserDefaults.standard.set(Self.schemaVersion, forKey: Self.schemaVersionKey)
        }

        do {
            container = try CadenceStore.makeModelContainer(inMemory: uiTest, cloudKitEnabled: cloud)
        } catch {
            // A dev schema change can leave an incompatible on-disk store.
            // Reset it once and retry rather than crashing (pre-release; sync
            // off by default so there's nothing remote to lose).
            CadenceStore.destroyDefaultStore()
            do {
                container = try CadenceStore.makeModelContainer(inMemory: uiTest, cloudKitEnabled: cloud)
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
        // Seed starter library and (in UI-test mode) deterministic fixtures.
        let ctx = ModelContext(container)
        _ = try? WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        if uiTest { UITestSeed.apply(args: args, context: ctx) }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
                .environment(settings)
                .environment(active)
        }
        .modelContainer(container)
    }
}
