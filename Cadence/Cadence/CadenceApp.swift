import SwiftUI
import SwiftData
import CadenceCore

@main
struct CadenceApp: App {
    @State private var model = AppModel()
    @State private var settings = AppSettings()
    let container: ModelContainer

    init() {
        let args = ProcessInfo.processInfo.arguments
        let uiTest = args.contains("-uiTest")
        let cloud = !uiTest && (UserDefaults.standard.object(forKey: SettingsKey.cloudSyncEnabled) as? Bool ?? false)
        do {
            container = try CadenceStore.makeModelContainer(inMemory: uiTest, cloudKitEnabled: cloud)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        // Seed starter library and (in UI-test mode) deterministic fixtures.
        let ctx = ModelContext(container)
        try? WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        if uiTest { UITestSeed.apply(args: args, context: ctx) }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                .environment(settings)
        }
        .modelContainer(container)
    }
}
