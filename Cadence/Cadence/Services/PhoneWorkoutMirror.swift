import HealthKit

/// Retains the iPhone's mirrored `HKWorkoutSession` for a Watch-primary workout.
/// Lifecycle only; HR packet transport is a separate follow-up.
@MainActor
final class PhoneWorkoutMirror: NSObject {
    private(set) var session: HKWorkoutSession?
    private(set) var generation = 0
    /// Test seam: invoked on every attach.
    var onAttach: ((HKWorkoutSession) -> Void)?

    func attach(_ session: HKWorkoutSession) {
        self.session = session
        generation &+= 1
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
            if toState == .ended { self.clear(workoutSession) }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.clear(workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        // TODO: decode HR sample packets in the follow-up packet issue.
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didDisconnectFromRemoteDeviceWithError error: Error?) {
        // TODO: follow-up packet issue may surface reconnect diagnostics.
        // HealthKit supplies a replacement mirrored session on reconnect.
        Task { @MainActor [weak self] in self?.clear(workoutSession) }
    }
}
