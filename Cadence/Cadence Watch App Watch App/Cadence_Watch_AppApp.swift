import SwiftUI
import SwiftData
import CadenceCore

@main
struct CadenceWatchApp: App {
    let container: ModelContainer = {
        do { return try CadenceStore.makeModelContainer() }
        catch { fatalError("Failed to create ModelContainer: \(error)") }
    }()

    @State private var watchManager = WatchWorkoutManager(uiTestMode: ProcessInfo.processInfo.arguments.contains("-uiTest"))

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(watchManager)
                .task { watchManager.activateWCSession() }
        }
        .modelContainer(container)
    }
}
