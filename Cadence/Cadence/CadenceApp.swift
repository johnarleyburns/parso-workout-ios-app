import SwiftUI
import SwiftData
import CadenceCore

@main
struct CadenceApp: App {
    @State private var model = AppModel()
    @State private var settings = AppSettings()
    @State private var active = ActiveWorkoutModel()
    @State private var contributions = ContributionCoordinator()
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

        // Reset a pre-version-2 local store once (pre-release; data is local and
        // back-up-able via export, so nothing irreplaceable is lost).
        if !uiTest, UserDefaults.standard.integer(forKey: Self.schemaVersionKey) < Self.schemaVersion {
            CadenceStore.destroyDefaultStore()
            UserDefaults.standard.set(Self.schemaVersion, forKey: Self.schemaVersionKey)
        }

        do {
            container = try CadenceStore.makeModelContainer(inMemory: uiTest)
        } catch {
            // A dev schema change can leave an incompatible on-disk store.
            // Reset it once and retry rather than crashing (pre-release; data is
            // local and export-backed, so nothing irreplaceable is lost).
            CadenceStore.destroyDefaultStore()
            do {
                container = try CadenceStore.makeModelContainer(inMemory: uiTest)
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
        // Seed starter library and (in UI-test mode) deterministic fixtures.
        let ctx = ModelContext(container)
        _ = try? WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        if uiTest { UITestSeed.apply(args: args, context: ctx) }
        // Restore the default BLE HRM for cold-launch auto-reconnect (FR-4.4).
        if !uiTest, let device = try? ctx.fetch(FetchDescriptor<HRMDevice>(predicate: #Predicate { $0.isDefault })).first {
            model.hrm.restoreDefaultDevice(device.id)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                .environment(settings)
                .environment(active)
                .environment(contributions)
                .task { model.activateWCSession() }
                .task { contributions.beginSession() }
        }
        .modelContainer(container)
    }
}
