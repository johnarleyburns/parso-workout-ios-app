import UIKit
import SwiftUI
import CadenceFeatures
#if canImport(CoreHaptics)
import CoreHaptics
#endif

/// Restrained, purposeful haptics (NFR-1). Distinct cues for set logged, new PR,
/// and rest complete (mirrors FR-8.5 on the watch later).
@MainActor
enum Haptics {
    #if canImport(CoreHaptics)
    private static var engine: CHHapticEngine?
    #endif
    /// Light selection tick when the user taps a navigational/actionable item —
    /// history rows, start/log tiles, primary buttons (batch 7 item 2, Apple HIG).
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func setLogged() {
        if playPattern(named: "SetLogged") != true { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }
    static func prAchieved() {
        if playPattern(named: "PRTakeover") != true { UINotificationFeedbackGenerator().notificationOccurred(.success) }
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

    @discardableResult
    private static func playPattern(named name: String) -> Bool? {
        #if canImport(CoreHaptics)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let url = Bundle.main.url(forResource: name, withExtension: "ahap"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let raw = object as? [String: Any],
              let version = raw["Version"],
              let events = raw["Pattern"] else { return nil }
        let dictionary: [CHHapticPattern.Key: Any] = [
            .version: version,
            .pattern: events
        ]
        guard let pattern = try? CHHapticPattern(dictionary: dictionary) else { return nil }
        do {
            if engine == nil { engine = try CHHapticEngine() }
            try engine?.start()
            try engine?.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
            return true
        } catch { return nil }
        #else
        return nil
        #endif
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
