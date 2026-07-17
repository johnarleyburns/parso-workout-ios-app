import Foundation

public enum WatchAuthPolicy {
    public enum ShareStatus: Equatable {
        case notDetermined
        case denied
        case authorized
    }

    public struct Decision: Equatable {
        public let canStart: Bool
        public let showDeniedWarning: Bool
        public let hrHint: Bool

        public init(canStart: Bool, showDeniedWarning: Bool, hrHint: Bool) {
            self.canStart = canStart
            self.showDeniedWarning = showDeniedWarning
            self.hrHint = hrHint
        }
    }

    public static func evaluate(shareStatus: ShareStatus, hrSampleSeen: Bool, sessionIsActive: Bool) -> Decision {
        let canStart = shareStatus == .authorized
        let showDeniedWarning = shareStatus == .denied
        let hrHint = sessionIsActive && !hrSampleSeen
        return Decision(canStart: canStart, showDeniedWarning: showDeniedWarning, hrHint: hrHint)
    }
}
