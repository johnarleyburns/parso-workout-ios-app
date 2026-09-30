import UIKit
import SwiftUI
import CadenceFeatures

/// Restrained, purposeful haptics (NFR-1). Distinct cues for set logged, new PR,
/// and rest complete (mirrors FR-8.5 on the watch later).
@MainActor
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
    static func intervalWork() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func intervalRest() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.65)
    }
    static func countdownWarning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func play(_ cue: CueKind) {
        switch cue {
        case .setLogged: setLogged()
        case .personalBest, .dayClosed: prAchieved()
        case .restEnding: countdownWarning()
        case .restDone: restComplete()
        case .intervalWork: intervalWork()
        case .intervalRest: intervalRest()
        case .undo: selection()
        }
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
