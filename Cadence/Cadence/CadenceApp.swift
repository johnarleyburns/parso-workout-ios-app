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

        // Put the audio session in non-interrupting mix mode before any audio
        // object initializes, so workout cues never pause the user's background
        // music/podcast (field-testing: warm-up silenced background audio).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                         options: [.mixWithOthers])

        do {
            container = try CadenceStore.makeModelContainer(inMemory: uiTest)
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
