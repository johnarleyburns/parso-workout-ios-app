import SwiftUI
import UIKit

/// Keeps the screen awake (disables iOS auto-lock) while a live workout, warm-up,
/// or cool-down is on screen, so the phone never locks mid-exercise (the user
/// reported it locking between sets / during intervals). Restores the system
/// default the moment the surface disappears, so battery is unaffected elsewhere.
private struct KeepAwakeModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { apply(active) }
            .onChange(of: active) { _, newValue in apply(newValue) }
            .onDisappear { apply(false) }
    }

    private func apply(_ value: Bool) {
        UIApplication.shared.isIdleTimerDisabled = value
    }
}

extension View {
    /// Disables auto-lock while `active` is true, restoring the default on
    /// disappear. Apply to live workout / warm-up / cool-down surfaces only.
    func keepAwake(_ active: Bool = true) -> some View {
        modifier(KeepAwakeModifier(active: active))
    }
}
