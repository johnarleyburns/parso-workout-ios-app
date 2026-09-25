import Foundation
import SwiftData

/// Gates the full built-in catalog reconciliation (`WorkoutRepository
/// .seedStarterLibraryIfNeeded`) so it runs when something could have changed,
/// not on every launch or foreground.
///
/// The reconciliation is idempotent but not cheap: it decodes the bundled DB++
/// database (~1.9 MB of JSON) into the ~900-entry starter catalog, fetches every
/// stored `Exercise` several times, and compares each row's facets. The iPhone
/// ran it on every `scenePhase == .active` and the Watch on every launch, so a
/// background context held the store while the UI's own fetches waited, and the
/// first main-thread touch of the catalog paid the DB++ decode.
///
/// It is skipped when three things all match the last successful run on this
/// device: the catalog revision (seed version + app build, so every new build
/// with new catalog data reconciles once), the stored exercise count, and the
/// newest stored exercise `updatedAt`. The last two are single cheap queries,
/// and they change whenever CloudKit imports or local edits add, delete, or
/// modify exercise rows.
public enum StarterLibraryReconciliation {
    public static let defaultsKey = "catalog.starterLibrary.reconciledSignature"

    /// The catalog revision that forces one reconciliation per app build.
    public static func revision(bundle: Bundle = .main) -> String {
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return "seed\(ExerciseLibrary.seedVersion)-build\(build)"
    }

    /// Cheap store fingerprint: exercise row count plus the newest `updatedAt`.
    /// It never materializes more than one `Exercise`.
    public static func storeSignature(_ context: ModelContext) throws -> String {
        let count = try context.fetchCount(FetchDescriptor<Exercise>())
        var newest = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        newest.fetchLimit = 1
        let latest = try context.fetch(newest).first?.updatedAt.timeIntervalSince1970 ?? 0
        return "\(count)|\(latest)"
    }

    /// Runs the full reconciliation only when the revision or the stored
    /// exercise rows changed since the last successful run. Returns whether the
    /// reconciliation ran, not whether it changed anything. Nothing is recorded
    /// when the reconciliation throws, so a failed run is retried next time.
    @discardableResult
    public static func reconcileIfStale(_ context: ModelContext,
                                        revision: String,
                                        defaults: UserDefaults = .standard) throws -> Bool {
        let before = "\(revision)#\(try storeSignature(context))"
        if defaults.string(forKey: defaultsKey) == before { return false }
        try WorkoutRepository.seedStarterLibraryIfNeeded(context)
        // Record the post-reconciliation fingerprint: the reconciliation's own
        // writes must not make the next launch look stale.
        defaults.set("\(revision)#\(try storeSignature(context))", forKey: defaultsKey)
        return true
    }
}

/// Decodes the lazily built catalogs on a background thread before the UI asks
/// for them. Swift `static let` initialization runs once, on whichever thread
/// touches it first, so without this the first main-thread use (Home volume,
/// exercise search, a template lookup in the workout screen) pays the full
/// DB++ decode while the UI waits.
public enum CatalogWarmup {
    public static func warm() {
        _ = TrainingEngineBridge.shared
        _ = ExerciseLibrary.starter.count
        _ = ExerciseLibrary.template(matching: "Bench Press")
        _ = VolumeCredit.direct
    }
}
