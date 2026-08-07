import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

@main
struct CadenceWatchApp: App {
    let container: ModelContainer = {
        do {
            let args = ProcessInfo.processInfo.arguments
            let uiTest = args.contains("-uiTest")
            let container = try CadenceStore.makeModelContainer(inMemory: uiTest, cloudKitEnabled: false)
            let context = ModelContext(container)
            _ = try? WorkoutRepository.seedStarterLibraryIfNeeded(context)
            if uiTest {
                for seed in CadenceWatchApp.seedNames(in: args) where seed.hasPrefix("person.") {
                    let name = String(seed.dropFirst("person.".count))
                    if !name.isEmpty { _ = try? WorkoutRepository.findOrCreatePerson(named: name, in: context) }
                }
            }
            return container
        }
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

    private static func seedNames(in args: [String]) -> Set<String> {
        var result: Set<String> = []
        var i = 0
        while i < args.count {
            if args[i] == "-seed", i + 1 < args.count { result.insert(args[i + 1]) }
            i += 1
        }
        return result
    }
}
