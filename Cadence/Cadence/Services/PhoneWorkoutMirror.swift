import CadenceFeatures
import HealthKit

/// Retains the iPhone's mirrored `HKWorkoutSession` for a Watch-primary workout.
/// Lifecycle only; HR packet transport is a separate follow-up.
@MainActor
final class PhoneWorkoutMirror: NSObject {
    private(set) var session: HKWorkoutSession?
    /// Tracks attach/disconnect/end/fail transitions through the tested
    /// `WorkoutMirrorLifecycle` reducer instead of ad hoc flags, so a stale
    /// callback from a superseded mirrored session can never be confused
    /// with the current one.
    private var lifecycle = WorkoutMirrorLifecycle()
    /// The generation the reducer assigned to the currently-held `session`.
    private var currentGeneration = 0
    /// Test seam: invoked on every attach.
    var onAttach: ((HKWorkoutSession) -> Void)?
    /// Raw packets received from the Watch's primary session (main actor).
    var onData: (([Data]) -> Void)?

    func attach(_ session: HKWorkoutSession) {
        self.session = session
        lifecycle.apply(.attached)
        currentGeneration = lifecycle.latestGeneration
        session.delegate = self
        onAttach?(session)
    }

    func clear(_ session: HKWorkoutSession) {
        guard self.session === session else { return }
        self.session = nil
    }
}

extension PhoneWorkoutMirror: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            if toState == .ended {
                self.lifecycle.apply(.ended(generation: self.currentGeneration))
                self.clear(workoutSession)
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.lifecycle.apply(.failed(generation: self.currentGeneration))
            self.clear(workoutSession)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        // NOTE: no identity/generation guard here yet — data is still
        // forwarded unconditionally. `lifecycle.shouldForwardData(generation:)`
        // is already proven correct in isolation (see
        // WorkoutMirrorLifecycleTests); wiring it into this call site to
        // reject stale-session data is a separate, stacked follow-up PR so
        // this one stays a pure internal refactor with no behavior change.
        Task { @MainActor [weak self] in self?.onData?(data) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didDisconnectFromRemoteDeviceWithError error: Error?) {
        // HealthKit supplies a replacement mirrored session on reconnect,
        // which is why the reducer has a distinct, recoverable
        // `.disconnected` state rather than treating this as terminal.
        // Today's production behavior still clears `session` immediately
        // on disconnect (unchanged by this refactor); a future change could
        // use `lifecycle`'s state to defer that decision.
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.lifecycle.apply(.disconnected(generation: self.currentGeneration))
            self.clear(workoutSession)
        }
    }
}
