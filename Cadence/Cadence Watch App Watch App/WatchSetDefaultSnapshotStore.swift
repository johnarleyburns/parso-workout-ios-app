import Foundation
import CadenceFeatures

/// Most recent valid phone set-default snapshot, kept across relaunch and iPhone absence.
/// Nothing reads it yet; it is deliberately outside SwiftData and triggers no UI refresh.
@MainActor
final class WatchSetDefaultSnapshotStore {
    static let shared = WatchSetDefaultSnapshotStore()

    private let persistence = WatchSetDefaultSnapshotPersistence()

    func load() -> WatchSetDefaultSnapshot? { persistence.load() }

    /// True when the snapshot replaced the stored one.
    @discardableResult
    func replaceIfNewer(_ snapshot: WatchSetDefaultSnapshot) -> Bool {
        persistence.replaceIfNewer(snapshot) == .replaced
    }

    /// Distinguishes "kept newer data" from "write failed" so the ACK path can refuse on failure.
    func persist(_ snapshot: WatchSetDefaultSnapshot) -> WatchSetDefaultSnapshotPersistence.Result {
        persistence.replaceIfNewer(snapshot)
    }
}
