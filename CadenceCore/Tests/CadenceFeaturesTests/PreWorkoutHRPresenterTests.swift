import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

/// Field test 2026-08-20 issue 6: the HR gate's Continue button must stay
/// tappable even when the Apple Watch fails to deliver a sample, and "Check for
/// Live HR" must never block on transient relay states. The view renders exactly
/// what this presenter returns, so the fix is asserted here rather than in the
/// simulator.
struct PreWorkoutHRPresenterTests {

    private func state(watchBPM: Int? = nil,
                       strapConnected: Bool = false,
                       watchRequested: Bool = false,
                       relayBusy: Bool = false) -> PreWorkoutHRState {
        PreWorkoutHRState(watchBPM: watchBPM,
                          strapConnected: strapConnected,
                          watchRequested: watchRequested,
                          relayBusy: relayBusy)
    }

    // MARK: continueEnabled — ALWAYS true (the fix)

    /// The exact field report: "Check for Live HR" was tapped, no sample ever
    /// arrived, no strap is connected — the screen used to be inoperable.
    @Test func continueIsEnabledWithNoHRAndWatchRequested() {
        let s = state(watchRequested: true)
        #expect(PreWorkoutHRPresenter.continueEnabled(s),
                      "Continue must stay enabled after a failed watch connection")
    }

    /// A relay mid-connection must not freeze the primary action either.
    @Test func continueIsEnabledWhileRelayBusy() {
        for busy in [false, true] {
            #expect(PreWorkoutHRPresenter.continueEnabled(state(relayBusy: busy)),
                          "Continue must be enabled while the relay is busy")
        }
    }

    @Test func continueIsEnabledInEveryState() {
        let states = [
            state(),
            state(watchRequested: true),
            state(watchBPM: 72),
            state(strapConnected: true),
            state(watchBPM: 72, strapConnected: true, watchRequested: true, relayBusy: true),
        ]
        for s in states {
            #expect(PreWorkoutHRPresenter.continueEnabled(s),
                          "Continue must never be disabled")
        }
    }

    // MARK: continueAction — source resolution

    @Test func continueActionWatchWhenLive() {
        #expect(PreWorkoutHRPresenter.continueAction(state(watchBPM: 121))
                       == .watch)
    }

    @Test func continueActionBluetoothWhenStrapConnected() {
        #expect(PreWorkoutHRPresenter.continueAction(state(strapConnected: true))
                       == .bluetooth)
    }

    @Test func continueActionNoneWhenNothingConnected() {
        #expect(PreWorkoutHRPresenter.continueAction(state())
                       == .none)
    }

    /// A live watch beats a connected strap: the watch session is the fresher,
    /// already-running source.
    @Test func continueActionWatchOutranksStrap() {
        #expect(PreWorkoutHRPresenter.continueAction(state(watchBPM: 90, strapConnected: true))
                       == .watch)
    }

    // MARK: continueLabel — matches the action

    @Test func continueLabelMatchesAction() {
        #expect(PreWorkoutHRPresenter.continueLabel(state(watchBPM: 121))
                       == "Continue with Apple Watch")
        #expect(PreWorkoutHRPresenter.continueLabel(state(strapConnected: true))
                       == "Continue with Bluetooth")
        #expect(PreWorkoutHRPresenter.continueLabel(state(watchRequested: true))
                       == "Continue without heart rate")
        #expect(PreWorkoutHRPresenter.continueLabel(state())
                       == "Continue without heart rate")
    }

    // MARK: checkEnabled — never blocks on transient relay states

    @Test func checkHRAalwaysEnabled() {
        for s in [
            state(),
            state(watchRequested: true),
            state(relayBusy: true),
            state(watchBPM: 72, strapConnected: true, watchRequested: true, relayBusy: true),
        ] {
            #expect(PreWorkoutHRPresenter.checkEnabled(s),
                          "Check for Live HR must never be disabled by a transient relay state")
        }
    }
}
