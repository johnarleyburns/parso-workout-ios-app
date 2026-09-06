import SwiftUI
import SwiftData
import AVFoundation
import CadenceCore
import CadenceFeatures

@main
@MainActor
struct CadenceApp: App {
    @State private var model = AppModel()
    @State private var settings = AppSettings()
    @State private var active = ActiveWorkoutModel()
    @State private var contributions = ContributionCoordinator()
    @State private var store = StoreService()
    let container: ModelContainer

    init() {
        let args = ProcessInfo.processInfo.arguments
        let uiTest = args.contains("-uiTest")
        let persistentUITest = args.contains("-uiTestPersistentStore")
        let uiTestStoreURL: URL? = {
            guard persistentUITest,
                  let idIndex = args.firstIndex(of: "-uiTestStoreID"),
                  args.indices.contains(idIndex + 1) else { return nil }
            let storeID = args[idIndex + 1].filter { $0.isNumber || $0 == "-" }
            guard !storeID.isEmpty,
                  let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                                     in: .userDomainMask).first else {
                return nil
            }
            try? FileManager.default.createDirectory(at: applicationSupport,
                                                     withIntermediateDirectories: true)
            return applicationSupport.appendingPathComponent("ui-test-\(storeID).store")
        }()

        // Put the audio session in non-interrupting mix mode before any audio
        // object initializes, so workout cues never pause the user's background
        // music/podcast (field-testing: warm-up silenced background audio).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                         options: [.mixWithOthers])

        do {
            container = try CadenceStore.makeModelContainer(
                inMemory: uiTest && !persistentUITest,
                cloudKitEnabled: !persistentUITest,
                storeURL: uiTestStoreURL)
        } catch {
            // Never delete or replace an on-disk store on a model-container
            // error. The store contains irreplaceable workout history and may
            // still be recoverable through SwiftData migration, CloudKit, or a
            // user export. Fail closed so a schema bug cannot become data loss.
            fatalError("Failed to create ModelContainer without altering stored workout history: \(error)")
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
                .environment(store)
                .environment(\.cadenceModelContainer, container)
                .task { model.activateWCSession() }
                .task { model.refreshCloudKitAccountStatus() }
                .task { WorkoutLiveActivityCoordinator.shared.endAllStale() }
                .task { model.configureWatchSync(settings: settings, container: container, active: active) }
                .task { contributions.beginSession() }
                .task { await store.start() }
        }
        .modelContainer(container)
    }
}
