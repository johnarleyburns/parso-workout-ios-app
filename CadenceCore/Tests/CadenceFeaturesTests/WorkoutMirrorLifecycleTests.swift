import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WorkoutMirrorLifecycleTests {
    @Test func firstAttach() {
        var l = WorkoutMirrorLifecycle()
        let startState = l.apply(.startRequested)
        #expect(startState == .starting)
        let attachedState = l.apply(.attached)
        #expect(attachedState == .mirrored(generation: 1))
    }

    @Test func reconnectReplacesAndIncrementsGeneration() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached)
        let state = l.apply(.attached)
        #expect(state == .mirrored(generation: 2))
    }

    @Test func oldSessionDisconnectCannotClearNewer() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached); l.apply(.attached)
        let disconnected1 = l.apply(.disconnected(generation: 1))
        #expect(disconnected1 == .mirrored(generation: 2))
        let failed1 = l.apply(.failed(generation: 1))
        #expect(failed1 == .mirrored(generation: 2))
        let disconnected2 = l.apply(.disconnected(generation: 2))
        #expect(disconnected2 == .disconnected(generation: 2))
    }

    @Test func endClearsOnlyCurrent() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached); l.apply(.attached)
        let ended1 = l.apply(.ended(generation: 1))
        #expect(ended1 == .mirrored(generation: 2))
        let ended2 = l.apply(.ended(generation: 2))
        #expect(ended2 == .inactive)
    }

    @Test func mirrorFailureStillStartsPrimary() {
        #expect(WorkoutMirrorLifecycle.shouldStartPrimary(mirrorSucceeded: false))
    }

    // MARK: - .disconnected is recoverable, not terminal

    @Test func endedAfterDisconnectTransitionsToInactiveInsteadOfStrandingState() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached) // .mirrored(1)
        let disconnected = l.apply(.disconnected(generation: 1))
        #expect(disconnected == .disconnected(generation: 1))
        // A genuine session-end arriving after the disconnect must not strand
        // the reducer in .disconnected forever.
        let ended = l.apply(.ended(generation: 1))
        #expect(ended == .inactive)
    }

    @Test func failedAfterDisconnectTransitionsToInactiveInsteadOfStrandingState() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached) // .mirrored(1)
        l.apply(.disconnected(generation: 1))
        let failed = l.apply(.failed(generation: 1))
        #expect(failed == .inactive)
    }

    @Test func staleEndedOrFailedWhileDisconnectedDoesNotClearNewerGeneration() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached); l.apply(.attached) // .mirrored(2)
        l.apply(.disconnected(generation: 2)) // .disconnected(2)
        // A stale generation-1 end/fail arriving late must not touch the
        // current generation-2 disconnected state.
        let ended = l.apply(.ended(generation: 1))
        #expect(ended == .disconnected(generation: 2))
        let failed = l.apply(.failed(generation: 1))
        #expect(failed == .disconnected(generation: 2))
    }

    // MARK: - Reconnect after disconnect

    @Test func reconnectAfterDisconnectProducesNewMirroredGeneration() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached) // .mirrored(1)
        let disconnected = l.apply(.disconnected(generation: 1))
        #expect(disconnected == .disconnected(generation: 1))
        // HealthKit supplies a replacement mirrored session on reconnect.
        let reattached = l.apply(.attached)
        #expect(reattached == .mirrored(generation: 2))
    }

    // MARK: - shouldForwardData

    @Test func shouldForwardDataOnlyTrueForCurrentMirroredGeneration() {
        var l = WorkoutMirrorLifecycle()
        #expect(!l.shouldForwardData(generation: 1)) // .inactive

        l.apply(.startRequested)
        #expect(!l.shouldForwardData(generation: 1)) // .starting

        l.apply(.attached) // .mirrored(1)
        #expect(l.shouldForwardData(generation: 1))
        #expect(!l.shouldForwardData(generation: 2)) // wrong generation

        l.apply(.attached) // reconnect: .mirrored(2)
        #expect(!l.shouldForwardData(generation: 1)) // stale/old generation
        #expect(l.shouldForwardData(generation: 2))

        l.apply(.disconnected(generation: 2)) // .disconnected(2)
        #expect(!l.shouldForwardData(generation: 2)) // not mirrored anymore
    }
}
