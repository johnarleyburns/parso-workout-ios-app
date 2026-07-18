import SwiftUI
import UIKit
import CadenceFeatures

/// App-wide keep-awake coordinator (launch-blockers Phase 1c). All surfaces
/// route through one reference-counted `IdleTimerArbiter`, whose holder union
/// maps onto `UIApplication.isIdleTimerDisabled`. This is state-driven — a
/// surface leaving the screen releases only ITS token, so the screen stays
/// awake as long as any holder (e.g. RootTabView while a workout is active)
/// remains. Previously a single boolean was flipped by whichever view
/// (dis)appeared last, so SessionView leaving re-enabled auto-lock mid-workout.
@MainActor
enum IdleTimerCoordinator {
    static let arbiter: IdleTimerArbiter = {
        let a = IdleTimerArbiter()
        a.apply = { UIApplication.shared.isIdleTimerDisabled = $0 }
        return a
    }()
}

private struct KeepAwakeModifier: ViewModifier {
    let active: Bool
    @State private var token = UUID().uuidString
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { update(active) }
            .onChange(of: active) { _, newValue in update(newValue) }
            .onDisappear { IdleTimerCoordinator.arbiter.release(token) }
            // iOS resets the idle timer on its own across some lifecycle
            // transitions; re-assert the union whenever we return to .active.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { IdleTimerCoordinator.arbiter.reassert() }
            }
    }

    private func update(_ value: Bool) {
        if value {
            IdleTimerCoordinator.arbiter.acquire(token)
        } else {
            IdleTimerCoordinator.arbiter.release(token)
        }
    }
}

extension View {
    /// Holds a keep-awake token while `active` is true. Tokens are
    /// reference-counted across surfaces (live session, HR gate, countdown,
    /// warm-up/cool-down, minimized-but-running workout), so the screen stays
    /// awake until the LAST holder releases.
    func keepAwake(_ active: Bool = true) -> some View {
        modifier(KeepAwakeModifier(active: active))
    }
}
