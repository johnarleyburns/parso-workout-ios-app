import SwiftUI
import SwiftData
import AVFoundation
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

@main
@MainActor
struct CadenceApp: App {
    @State private var model = AppModel()
    @State private var settings = AppSettings()
    @State private var active = ActiveWorkoutModel()
    @State private var contributions = ContributionCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    let container: ModelContainer
    /// Non-`.ready` when the on-disk store couldn't be opened and had to be
    /// quarantined and/or replaced with an in-memory container (issue #779).
    /// Surfaced as a small banner in `body`; never a blocking screen.
    @State private var storeRecoveryState: WatchStoreBootstrapPolicy<ModelContainer>.State
    /// Store preparation is per process, not per foreground. It used to rerun
    /// the whole catalog reconciliation and a full-history index check every
    /// time the app became active.
    @State private var persistentStorePrepared = false

    init() {
        // Put the audio session in non-interrupting mix mode before any audio
        // object initializes, so workout cues never pause the user's background
        // music/podcast (field-testing: warm-up silenced background audio).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                         options: [.mixWithOthers])

        // issue #779: a corrupted/incompatible on-disk store previously
        // propagated out of `makeApplicationModelContainer()` straight to an
        // unconditional `fatalError`, with no recovery path — unlike the
        // Watch app, which already quarantines, retries, and falls back to
        // an in-memory container. Reuse that exact combinator here instead of
        // inventing new recovery logic. Quarantine only ever moves files
        // aside into a timestamped recovery directory; it never deletes an
        // on-disk store, so the "never delete or replace stored workout
        // history" guarantee still holds even after this change.
        let policy = WatchStoreBootstrapPolicy<ModelContainer>(
            createPersistent: { try CadenceStore.makeApplicationModelContainer() },
            createInMemory: { try CadenceStore.makeModelContainer(inMemory: true) },
            quarantine: { try Self.quarantinePhoneStore() },
            seed: { _ in })
        let outcome = policy.open()
        guard let resolvedContainer = outcome.container else {
            // Only reachable if even an in-memory container can't be created —
            // there is no store left to fail closed over at that point.
            fatalError("Failed to create any ModelContainer, including in-memory, without altering stored workout history")
        }
        container = resolvedContainer
        _storeRecoveryState = State(initialValue: outcome.state)
        // Attach before the first scene task so an import that starts during
        // ModelContainer setup can still surface its restore state in the UI.
        model.startCloudKitHistoryMonitoring()
    }

    /// Moves aside (never deletes) whichever on-disk store files exist — the
    /// pre-split store during a failed one-time copy, or the current split
    /// Local/Sync — into a timestamped recovery directory, mirroring the Watch
    /// app's own `quarantineStore()`.
    private static func quarantinePhoneStore() throws -> URL? {
        let fm = FileManager.default
        let directory = CadenceStore.applicationSupportDirectory()
        let baseNames = [CadenceStore.legacyStoreFileName, CadenceStore.localStoreFileName,
                         CadenceStore.syncStoreFileName]
        let names = baseNames.flatMap { [$0, $0 + "-shm", $0 + "-wal"] }
        let existing = names.map { directory.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }
        let recovery = WatchStoreFiles.recoveryDirectory(in: directory)
        try fm.createDirectory(at: recovery, withIntermediateDirectories: true)
        for file in existing {
            try fm.moveItem(at: file, to: recovery.appendingPathComponent(file.lastPathComponent))
        }
        return recovery
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                .environment(settings)
                .environment(active)
                .environment(contributions)
                .environment(\.cadenceModelContainer, container)
                .overlay(alignment: .top) { storeRecoveryBanner }
                .task { model.activateWCSession() }
                .task { model.refreshCloudKitAccountStatus() }
                .task { await model.finishLegacyStoreUpgrade(container: container, settings: settings) }
                .task { _ = await model.healthBackup.drain() }
                .task { model.configureWatchSync(settings: settings, container: container, active: active) }
                .task { contributions.beginSession() }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    model.setApplicationActive(phase == .active)
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active, !persistentStorePrepared else { return }
                    if await preparePersistentStore() {
                        persistentStorePrepared = true
                    }
                }
        }
        .modelContainer(container)
    }

    /// issue #779: a non-blocking, dismissible notice — never a full-screen
    /// takeover — shown only when `init()` had to quarantine and/or fall back
    /// to an in-memory store. Transparency over silence: the user is told
    /// what happened and how to export their data rather than the app just
    /// silently running in a degraded state.
    @ViewBuilder private var storeRecoveryBanner: some View {
        switch storeRecoveryState {
        case .ready:
            EmptyView()
        case .recovered:
            StoreRecoveryBanner(
                message: String(localized: "A local data issue was found and recovered automatically. Your previous store was kept, not deleted — open Settings → Backup & Restore to export a copy."),
                dismiss: { storeRecoveryState = .ready })
        case .degraded, .opening, .quarantining, .retrying, .idle:
            StoreRecoveryBanner(
                message: String(localized: "Cladiron is running with a temporary store after a local data issue. Restart the app, and open Settings → Backup & Restore to export or restore your data."),
                dismiss: { storeRecoveryState = .ready })
        }
    }

    private func preparePersistentStore() async -> Bool {
        // Give SwiftUI a frame for the launch surface before doing synchronous
        // SwiftData seeding. The seed can touch hundreds of exercises during a
        // catalog upgrade, so it must also run in a detached context; a single
        // yield only postpones the freeze, it does not move the work off the
        // main actor.
        await Task.yield()
        guard !Task.isCancelled else { return false }
        let container = container
        let catalogRevision = StarterLibraryReconciliation.revision()
        // A detached task does not inherit cancellation from the scene task. If
        // the user backgrounds during this store work, explicitly cancel it so
        // a SwiftData context cannot keep the SQLite/CloudKit store open while
        // iOS suspends the process (RUNNINGBOARD 0xdead10cc).
        let preparation = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return nil as UUID? }
            // Decode the bundled DB++ catalog here, off the main actor, so the
            // first Home volume, search, or template lookup does not pay it
            // while the UI waits.
            CatalogWarmup.warm()
            guard !Task.isCancelled else { return nil as UUID? }
            let ctx = ModelContext(container)
            // Full reconciliation only when the build or stored exercise rows
            // changed since the last successful run.
            _ = try? StarterLibraryReconciliation.reconcileIfStale(ctx, revision: catalogRevision)
            guard !Task.isCancelled else { return nil as UUID? }
            // Build the app-only Personalized projection from the complete
            // canonical history during store preparation. This includes old
            // workouts on existing installs before the user opens Suggestions;
            // the request path independently verifies the source signature.
            if let history = try? WorkoutRepository.allSessions(ctx) {
                _ = try? ExerciseHistoryIndexStore.rebuildIfNeeded(sessions: history)
            }
            guard !Task.isCancelled else { return nil as UUID? }
            return try? ctx.fetch(FetchDescriptor<HRMDevice>(predicate: #Predicate { $0.isDefault }))
                .first?.id
        }
        let defaultDeviceID = await withTaskCancellationHandler(operation: {
            await preparation.value
        }, onCancel: {
            preparation.cancel()
        })

        guard !Task.isCancelled else { return false }

        // Restore the default BLE HRM for cold-launch auto-reconnect (FR-4.4).
        if let defaultDeviceID {
            model.hrm.restoreDefaultDevice(defaultDeviceID)
        }
        return true
    }
}

/// Minimal non-blocking banner for the store-recovery notice (issue #779).
/// Deliberately not a full-screen flow — the app keeps working underneath.
private struct StoreRecoveryBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Dismiss"))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}
