import CadenceFeatures
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
                healthTitle: {
                    #if os(Linux)
                    "Apple Health backup is off"
                    #else
                    String(localized: "Apple Health backup is off", bundle: FeatureLocalization.bundle)
                    #endif
                }(),
                healthDetail: {
                    #if os(Linux)
                    "Completed workouts remain in Cladiron and its configured private backup."
                    #else
                    String(localized: "Completed workouts remain in Cladiron and its configured private backup.", bundle: FeatureLocalization.bundle)
                    #endif
                }())
        }
        if let error = lastHealthError, !error.isEmpty {
            return BackupCenterStatus(
                health: .attention(error),
                healthTitle: {
                    #if os(Linux)
                    "Apple Health needs attention"
                    #else
                    String(localized: "Apple Health needs attention", bundle: FeatureLocalization.bundle)
                    #endif
                }(),
                healthDetail: {
                    #if os(Linux)
                    "Cladiron will keep retrying the queued backup. You can retry now."
                    #else
                    String(localized: "Cladiron will keep retrying the queued backup. You can retry now.", bundle: FeatureLocalization.bundle)
                    #endif
                }())
        }
        if pendingHealthItems > 0 {
            return BackupCenterStatus(
                health: .waiting(pendingHealthItems),
                healthTitle: {
                    #if os(Linux)
                    "Apple Health backup is waiting"
                    #else
                    String(localized: "Apple Health backup is waiting", bundle: FeatureLocalization.bundle)
                    #endif
                }(),
                healthDetail: {
                    #if os(Linux)
                    "\(pendingHealthItems) items waiting to be saved."
                    #else
                    String(localized: "\(pendingHealthItems) items waiting to be saved.", bundle: FeatureLocalization.bundle)
                    #endif
                }())
        }
        return BackupCenterStatus(
            health: .current,
            healthTitle: {
                #if os(Linux)
                "Apple Health backup is current"
                #else
                String(localized: "Apple Health backup is current", bundle: FeatureLocalization.bundle)
                #endif
            }(),
            healthDetail: {
                #if os(Linux)
                "Cladiron-authored workout summaries and supported fitness tests are backed up when Health accepts them."
                #else
                String(localized: "Cladiron-authored workout summaries and supported fitness tests are backed up when Health accepts them.", bundle: FeatureLocalization.bundle)
                #endif
            }())
    }

    public static func restoreSummary(inserted: Int, replaced: Int, skipped: Int) -> String {
        let changed = inserted + replaced
        if changed == 0 {
            return skipped == 0
                ? {
                    #if os(Linux)
                    "No new Cladiron workouts were found. Health read access may be off or Health may still be syncing."
                    #else
                    String(localized: "No new Cladiron workouts were found. Health read access may be off or Health may still be syncing.", bundle: FeatureLocalization.bundle)
                    #endif
                }()
                : {
                    #if os(Linux)
                    "No rows changed; \(skipped) existing rows were already current."
                    #else
                    String(localized: "No rows changed; \(skipped) existing rows were already current.", bundle: FeatureLocalization.bundle)
                    #endif
                }()
        }
        var parts = [{
            #if os(Linux)
            "Restored \(changed) workouts"
            #else
            String(localized: "Restored \(changed) workouts", bundle: FeatureLocalization.bundle)
            #endif
        }()]
        if replaced > 0 { parts.append({
            #if os(Linux)
            "\(replaced) newer Health versions applied"
            #else
            String(localized: "\(replaced) newer Health versions applied", bundle: FeatureLocalization.bundle)
            #endif
        }()) }
        if skipped > 0 { parts.append({
            #if os(Linux)
            "\(skipped) already current"
            #else
            String(localized: "\(skipped) already current", bundle: FeatureLocalization.bundle)
            #endif
        }()) }
        return parts.joined(separator: " · ") + "."
    }
}
