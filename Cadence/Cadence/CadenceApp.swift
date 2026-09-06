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
    private let uiTestMode: Bool
    let container: ModelContainer

    init() {
        let args = ProcessInfo.processInfo.arguments
        let uiTest = args.contains("-uiTest")
        self.uiTestMode = uiTest
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
        // Attach before the first scene task so an import that starts during
        // ModelContainer setup can still surface its restore state in the UI.
        model.startCloudKitHistoryMonitoring()
        // UI tests need deterministic fixtures before their first assertion. In
        // production this work is deferred until after the first frame so a
        // CloudKit restore and a large exercise-library seed cannot monopolize
        // app launch.
        if uiTest {
            let ctx = ModelContext(container)
            _ = try? WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
            UITestSeed.apply(args: args, context: ctx)
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
                .task { await preparePersistentStore() }
                .task { await store.start() }
        }
        .modelContainer(container)
    }

    private func preparePersistentStore() async {
        guard !uiTestMode else { return }
        // Give SwiftUI a frame for the launch surface before doing synchronous
        // SwiftData seeding. ModelContext is actor-bound, so yielding here is
        // the safe way to move this work after first render without passing
        // managed objects across actors.
        await Task.yield()
        let ctx = ModelContext(container)
        _ = try? WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        // Restore the default BLE HRM for cold-launch auto-reconnect (FR-4.4).
        if let device = try? ctx.fetch(FetchDescriptor<HRMDevice>(predicate: #Predicate { $0.isDefault })).first {
            model.hrm.restoreDefaultDevice(device.id)
        }
    }
}
