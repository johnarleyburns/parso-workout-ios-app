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
                healthTitle: String(localized: "Apple Health backup is off", bundle: .module),
                healthDetail: String(localized: "Completed workouts remain in Cladiron and its configured private backup.", bundle: .module))
        }
        if let error = lastHealthError, !error.isEmpty {
            return BackupCenterStatus(
                health: .attention(error),
                healthTitle: String(localized: "Apple Health needs attention", bundle: .module),
                healthDetail: String(localized: "Cladiron will keep retrying the queued backup. You can retry now.", bundle: .module))
        }
        if pendingHealthItems > 0 {
            return BackupCenterStatus(
                health: .waiting(pendingHealthItems),
                healthTitle: String(localized: "Apple Health backup is waiting", bundle: .module),
                healthDetail: String(localized: "\(pendingHealthItems) items waiting to be saved.", bundle: .module))
        }
        return BackupCenterStatus(
            health: .current,
            healthTitle: String(localized: "Apple Health backup is current", bundle: .module),
            healthDetail: String(localized: "Cladiron-authored workout summaries and supported fitness tests are backed up when Health accepts them.", bundle: .module))
    }

    public static func restoreSummary(inserted: Int, replaced: Int, skipped: Int) -> String {
        let changed = inserted + replaced
        if changed == 0 {
            return skipped == 0
                ? String(localized: "No new Cladiron workouts were found. Health read access may be off or Health may still be syncing.", bundle: .module)
                : String(localized: "No rows changed; \(skipped) existing rows were already current.", bundle: .module)
        }
        var parts = [String(localized: "Restored \(changed) workouts", bundle: .module)]
        if replaced > 0 { parts.append(String(localized: "\(replaced) newer Health versions applied", bundle: .module)) }
        if skipped > 0 { parts.append(String(localized: "\(skipped) already current", bundle: .module)) }
        return parts.joined(separator: " · ") + "."
    }
}
