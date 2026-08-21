import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Field test 2026-08-20 issue 6: the HR gate's Continue button must stay
/// tappable even when the Apple Watch fails to deliver a sample, and "Check for
/// Live HR" must never block on transient relay states. The view renders exactly
/// what this presenter returns, so the fix is asserted here rather than in the
/// simulator.
final class PreWorkoutHRPresenterTests: XCTestCase {

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
    func testContinueIsEnabledWithNoHRAndWatchRequested() {
        let s = state(watchRequested: true)
        XCTAssertTrue(PreWorkoutHRPresenter.continueEnabled(s),
                      "Continue must stay enabled after a failed watch connection")
    }

    /// A relay mid-connection must not freeze the primary action either.
    func testContinueIsEnabledWhileRelayBusy() {
        for busy in [false, true] {
            XCTAssertTrue(PreWorkoutHRPresenter.continueEnabled(state(relayBusy: busy)),
                          "Continue must be enabled while the relay is busy")
        }
    }

    func testContinueIsEnabledInEveryState() {
        let states = [
            state(),
            state(watchRequested: true),
            state(watchBPM: 72),
            state(strapConnected: true),
            state(watchBPM: 72, strapConnected: true, watchRequested: true, relayBusy: true),
        ]
        for s in states {
            XCTAssertTrue(PreWorkoutHRPresenter.continueEnabled(s),
                          "Continue must never be disabled")
        }
    }

    // MARK: continueAction — source resolution

    func testContinueActionWatchWhenLive() {
        XCTAssertEqual(PreWorkoutHRPresenter.continueAction(state(watchBPM: 121)),
                       .watch)
    }

    func testContinueActionBluetoothWhenStrapConnected() {
        XCTAssertEqual(PreWorkoutHRPresenter.continueAction(state(strapConnected: true)),
                       .bluetooth)
    }

    func testContinueActionNoneWhenNothingConnected() {
        XCTAssertEqual(PreWorkoutHRPresenter.continueAction(state()),
                       .none)
    }

    /// A live watch beats a connected strap: the watch session is the fresher,
    /// already-running source.
    func testContinueActionWatchOutranksStrap() {
        XCTAssertEqual(PreWorkoutHRPresenter.continueAction(state(watchBPM: 90, strapConnected: true)),
                       .watch)
    }

    // MARK: continueLabel — matches the action

    func testContinueLabelMatchesAction() {
        XCTAssertEqual(PreWorkoutHRPresenter.continueLabel(state(watchBPM: 121)),
                       "Continue with Apple Watch")
        XCTAssertEqual(PreWorkoutHRPresenter.continueLabel(state(strapConnected: true)),
                       "Continue with Bluetooth")
        XCTAssertEqual(PreWorkoutHRPresenter.continueLabel(state(watchRequested: true)),
                       "Continue without heart rate")
        XCTAssertEqual(PreWorkoutHRPresenter.continueLabel(state()),
                       "Continue without heart rate")
    }

    // MARK: checkEnabled — never blocks on transient relay states

    func testCheckHRAalwaysEnabled() {
        for s in [
            state(),
            state(watchRequested: true),
            state(relayBusy: true),
            state(watchBPM: 72, strapConnected: true, watchRequested: true, relayBusy: true),
        ] {
            XCTAssertTrue(PreWorkoutHRPresenter.checkEnabled(s),
                          "Check for Live HR must never be disabled by a transient relay state")
        }
    }
}
