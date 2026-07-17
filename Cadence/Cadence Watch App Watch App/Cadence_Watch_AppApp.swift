import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

@main
struct CadenceWatchApp: App {
    let container: ModelContainer = {
        do { return try CadenceStore.makeModelContainer() }
        catch { fatalError("Failed to create ModelContainer: \(error)") }
    }()

    @State private var watchManager = WatchWorkoutManager(uiTestMode: ProcessInfo.processInfo.arguments.contains("-uiTest"))
    @State private var watchAppSettings: AppSettings = {
        let s = AppSettings()
        if s.unit == .kilograms {
            s.unit = WeightIncrement.unitDefault()
        }
        return s
    }()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(watchManager)
                .environment(watchAppSettings)
                .task { watchManager.activateWCSession() }
                .task { watchManager.watchAppSettings = watchAppSettings }
        }
        .modelContainer(container)
    }
}
