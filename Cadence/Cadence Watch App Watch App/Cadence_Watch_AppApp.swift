import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import os.log

@main
@MainActor
struct CadenceWatchApp: App {
    let bootstrap: WatchStoreBootstrap

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
            if let container = bootstrap.container, !bootstrap.isRecovery {
                Group {
                    VStack(spacing: 0) {
                        if let message = bootstrap.recoveryMessage {
                            Label(message, systemImage: "externaldrive.badge.checkmark")
                                .font(.caption2).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).padding(.horizontal, 8).padding(.top, 4)
                        }
                        WatchRootView()
                    }
                        .environment(watchManager)
                        .environment(watchAppSettings)
                        .task { watchManager.activateWCSession() }
                        .task { watchManager.watchAppSettings = watchAppSettings }
                }
                .modelContainer(container)
            } else {
                WatchStoreRecoveryView(bootstrap: bootstrap, watchManager: watchManager)
            }
        }
    }

    init() {
        bootstrap = WatchStoreBootstrap(arguments: ProcessInfo.processInfo.arguments)
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

/// Nonfatal Watch-local store bootstrap. It quarantines only the three SwiftData
/// default-store files and leaves the app usable even when persistence is broken.
@MainActor
final class WatchStoreBootstrap: ObservableObject {
    enum State { case ready, recovered(URL), degraded(Error) }
    @Published private(set) var state: State = .ready
    @Published private(set) var container: ModelContainer?
    private var retryInProgress = false
    private static let logger = Logger(subsystem: "com.cladiron.app", category: "WatchStoreBootstrap")

    var isRecovery: Bool {
        if case .degraded = state { return true }
        return container == nil
    }

    var recoveryMessage: String? {
        if case .recovered(let url) = state {
            return "Previous Watch data was recovered to \(url.lastPathComponent)."
        }
        return nil
    }

    init(arguments: [String]) {
        let inMemory = arguments.contains("-uiTest")
        do {
            let fresh = try CadenceStore.makeModelContainer(inMemory: inMemory, cloudKitEnabled: false)
            container = fresh
            seed(fresh, arguments: arguments)
        } catch {
            let quarantine: URL?
            do {
                quarantine = try Self.quarantineStore()
            } catch {
                Self.logger.error("Store quarantine failed: \(error.localizedDescription, privacy: .public)")
                quarantine = nil
            }
            do {
                let fresh = try CadenceStore.makeModelContainer(inMemory: false, cloudKitEnabled: false)
                container = fresh
                state = .recovered(quarantine ?? FileManager.default.temporaryDirectory)
                seed(fresh, arguments: arguments)
            } catch let retryError {
                do {
                    container = try CadenceStore.makeModelContainer(inMemory: true, cloudKitEnabled: false)
                    state = .degraded(retryError)
                } catch {
                    // Keep the recovery surface alive even if the platform cannot
                    // create an in-memory host; no workout UI is presented.
                    container = nil
                }
            }
        }
    }

    func retry() {
        guard !retryInProgress else { return }
        retryInProgress = true
        defer { retryInProgress = false }
        do {
            let fresh = try CadenceStore.makeModelContainer(inMemory: false, cloudKitEnabled: false)
            container = fresh
            seed(fresh, arguments: ProcessInfo.processInfo.arguments)
            state = .ready
        } catch {
            Self.logger.error("Store retry failed: \(error.localizedDescription, privacy: .public)")
            state = .degraded(error)
        }
    }

    private func seed(_ container: ModelContainer, arguments: [String]) {
        let context = ModelContext(container)
        _ = try? WorkoutRepository.seedStarterLibraryIfNeeded(context)
        for seed in Self.seedNames(in: arguments) where seed.hasPrefix("person.") {
            let name = String(seed.dropFirst("person.".count))
            if !name.isEmpty { _ = try? WorkoutRepository.findOrCreatePerson(named: name, in: context) }
        }
    }

    private static func quarantineStore() throws -> URL? {
        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let names = WatchStoreFiles.exactNames
        let existing = names.map { support.appendingPathComponent($0) }.filter { fm.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }
        let recovery = WatchStoreFiles.recoveryDirectory(in: support)
        try fm.createDirectory(at: recovery, withIntermediateDirectories: false)
        for file in existing {
            try fm.moveItem(at: file, to: recovery.appendingPathComponent(file.lastPathComponent))
        }
        return recovery
    }

    private static func seedNames(in args: [String]) -> Set<String> {
        var result: Set<String> = []
        var i = 0
        while i < args.count { if args[i] == "-seed", i + 1 < args.count { result.insert(args[i + 1]) }; i += 1 }
        return result
    }
}


private struct WatchStoreRecoveryView: View {
    @ObservedObject var bootstrap: WatchStoreBootstrap
    let watchManager: WatchWorkoutManager
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.title2)
            Text("Watch storage needs attention").font(.headline).multilineTextAlignment(.center)
            Text("Your iPhone data is unaffected. The Watch is using a temporary store until it can try again.")
                .font(.caption).multilineTextAlignment(.center)
            Button("Try Again") { bootstrap.retry() }.accessibilityIdentifier("watch.storeRecovery.retry")
            Button("Sync from iPhone") {
                watchManager.requestSettingsSync()
                bootstrap.retry()
            }.accessibilityIdentifier("watch.storeRecovery.syncPhone")
        }
        .padding()
        .accessibilityIdentifier("watch.storeRecovery")
    }
}
