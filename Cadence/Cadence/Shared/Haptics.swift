import UIKit
import SwiftUI

/// Restrained, purposeful haptics (NFR-1). Distinct cues for set logged, new PR,
/// and rest complete (mirrors FR-8.5 on the watch later).
enum Haptics {
    /// Light selection tick when the user taps a navigational/actionable item —
    /// history rows, start/log tiles, primary buttons (batch 7 item 2, Apple HIG).
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
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

extension View {
    /// Adds a light selection tick when this view is tapped, without consuming the
    /// tap — composes alongside a `Button`/grid `NavigationLink` action (batch 7
    /// item 2). NOTE: do not use on a `List`-row `NavigationLink` — the simultaneous
    /// gesture swallows the row's push there; add `Haptics.selection()` inline in a
    /// `Button` row instead.
    func tapHaptic() -> some View {
        simultaneousGesture(TapGesture().onEnded { Haptics.selection() })
    }
}
