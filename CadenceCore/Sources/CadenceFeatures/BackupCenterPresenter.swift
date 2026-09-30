import Foundation

/// Pure copy/state rules for the Backup & Restore center. The view supplies
/// platform facts (HealthKit availability, outbox count, and restore result),
/// while this type keeps the user-facing explanation deterministic and tested.
public enum BackupHealthState: Equatable, Sendable {
    case disabled
    case current
    case waiting(Int)
    case attention(String)
}

public struct BackupCenterStatus: Equatable, Sendable {
    public let health: BackupHealthState
    public let healthTitle: String
    public let healthDetail: String

    public init(health: BackupHealthState, healthTitle: String, healthDetail: String) {
        self.health = health
        self.healthTitle = healthTitle
        self.healthDetail = healthDetail
    }
}

public enum BackupCenterPresenter {
    public static func status(autoSaveHealth: Bool,
                              pendingHealthItems: Int,
                              lastHealthError: String?) -> BackupCenterStatus {
        guard autoSaveHealth else {
            return BackupCenterStatus(
                health: .disabled,
                healthTitle: "Apple Health backup is off",
                healthDetail: "Completed workouts remain in Cladiron and its configured private backup.")
        }
        if let error = lastHealthError, !error.isEmpty {
            return BackupCenterStatus(
                health: .attention(error),
                healthTitle: "Apple Health needs attention",
                healthDetail: "Cladiron will keep retrying the queued backup. You can retry now.")
        }
        if pendingHealthItems > 0 {
            return BackupCenterStatus(
                health: .waiting(pendingHealthItems),
                healthTitle: "Apple Health backup is waiting",
                healthDetail: "\(pendingHealthItems) item\(pendingHealthItems == 1 ? "" : "s") waiting to be saved.")
        }
        return BackupCenterStatus(
            health: .current,
            healthTitle: "Apple Health backup is current",
            healthDetail: "Cladiron-authored workout summaries and supported fitness tests are backed up when Health accepts them.")
    }

    public static func restoreSummary(inserted: Int, replaced: Int, skipped: Int) -> String {
        let changed = inserted + replaced
        if changed == 0 {
            return skipped == 0
                ? "No new Cladiron workouts were found. Health read access may be off or Health may still be syncing."
                : "No rows changed; \(skipped) existing row\(skipped == 1 ? " was" : "s were") already current."
        }
        var parts = ["Restored \(changed) workout\(changed == 1 ? "" : "s")"]
        if replaced > 0 { parts.append("\(replaced) newer Health version\(replaced == 1 ? "" : "s") applied") }
        if skipped > 0 { parts.append("\(skipped) already current") }
        return parts.joined(separator: " · ") + "."
    }
}
