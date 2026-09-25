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
    @Environment(\.scenePhase) private var scenePhase
    private let uiTestMode: Bool
    let container: ModelContainer
    /// Store preparation is per process, not per foreground. It used to rerun
    /// the whole catalog reconciliation and a full-history index check every
    /// time the app became active.
    @State private var persistentStorePrepared = false

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
                .environment(\.cadenceModelContainer, container)
                .task { model.activateWCSession() }
                .task { model.refreshCloudKitAccountStatus() }
                .task { WorkoutLiveActivityCoordinator.shared.endAllStale() }
                .task { model.configureWatchSync(settings: settings, container: container, active: active) }
                .task { contributions.beginSession() }
                .task(id: scenePhase) {
                    guard scenePhase == .active, !persistentStorePrepared else { return }
                    persistentStorePrepared = true
                    await preparePersistentStore()
                }
        }
        .modelContainer(container)
    }

    private func preparePersistentStore() async {
        guard !uiTestMode else { return }
        // Give SwiftUI a frame for the launch surface before doing synchronous
        // SwiftData seeding. The seed can touch hundreds of exercises during a
        // catalog upgrade, so it must also run in a detached context; a single
        // yield only postpones the freeze, it does not move the work off the
        // main actor.
        await Task.yield()
        let container = container
        let catalogRevision = StarterLibraryReconciliation.revision()
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Prepare exercise catalog")
        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
        let defaultDeviceID = await Task.detached(priority: .utility) {
            // Decode the bundled DB++ catalog here, off the main actor, so the
            // first Home volume, search, or template lookup does not pay it
            // while the UI waits.
            CatalogWarmup.warm()
            let ctx = ModelContext(container)
            // Full reconciliation only when the build or stored exercise rows
            // changed since the last successful run.
            _ = try? StarterLibraryReconciliation.reconcileIfStale(ctx, revision: catalogRevision)
            // Build the app-only Personalized projection from the complete
            // canonical history during store preparation. This includes old
            // workouts on existing installs before the user opens Suggestions;
            // the request path independently verifies the source signature.
            if let history = try? WorkoutRepository.allSessions(ctx) {
                _ = try? ExerciseHistoryIndexStore.rebuildIfNeeded(sessions: history)
            }
            return try? ctx.fetch(FetchDescriptor<HRMDevice>(predicate: #Predicate { $0.isDefault }))
                .first?.id
        }.value

        // Restore the default BLE HRM for cold-launch auto-reconnect (FR-4.4).
        if let defaultDeviceID {
            model.hrm.restoreDefaultDevice(defaultDeviceID)
        }
    }
}
