import UIKit

/// Restrained, purposeful haptics (NFR-1). Distinct cues for set logged, new PR,
/// and rest complete (mirrors FR-8.5 on the watch later).
enum Haptics {
    static func setLogged() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func prAchieved() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func restComplete() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
