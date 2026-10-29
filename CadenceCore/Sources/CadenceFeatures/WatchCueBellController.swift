import Foundation

public enum WatchBellKind: Sendable, Equatable {
    case phase, warning
}

public enum WatchBellEvent: Sendable, Equatable {
    case finished(UUID)
    case failed(UUID)
}

@MainActor
public protocol WatchCueBellDriving: AnyObject {
    var onEvent: (@MainActor @Sendable (WatchBellEvent) -> Void)? { get set }
    /// Creates a fresh playback, prepares and plays it. False when the asset is missing or play fails.
    func start(id: UUID, kind: WatchBellKind) -> Bool
    func stop(id: UUID)
}

/// Lifecycle of bell playback: one lease per strike, retired by playback identity.
@MainActor
public final class WatchCueBellController {
    private struct Playing { let owner: UUID; let lease: WatchCueLease }
    private struct Sequence { let id: UUID; var tasks: [any WatchCueCancellable] }

    private let audio: WatchCueAudioCoordinator
    private let driver: any WatchCueBellDriving
    private let scheduler: any WatchCueScheduling
    private let makeID: @MainActor () -> UUID
    private let offsets: [TimeInterval]
    private var playing: [UUID: Playing] = [:]
    private var sequences: [UUID: Sequence] = [:]

    public var playingCount: Int { playing.count }

    public init(audio: WatchCueAudioCoordinator, driver: any WatchCueBellDriving,
                scheduler: any WatchCueScheduling,
                restCompletionOffsets: [TimeInterval] = WatchWorkoutCuePolicy.restCompletionBellOffsets,
                makeID: @escaping @MainActor () -> UUID = { UUID() }) {
        self.audio = audio
        self.driver = driver
        self.scheduler = scheduler
        self.offsets = restCompletionOffsets
        self.makeID = makeID
        driver.onEvent = { [weak self] event in
            switch event {
            case .finished(let id), .failed(let id): self?.retire(id)
            }
        }
        audio.addInvalidationHandler { [weak self] _ in self?.cancelAllWorkoutBells() }
    }

    public func play(_ kind: WatchBellKind, owner: UUID, enabled: Bool) {
        guard enabled else { return }
        start(kind, owner: owner)
    }

    /// Three bells at the policy offsets; each acquires only when it actually starts.
    public func restComplete(owner: UUID, enabled: Bool) {
        guard enabled else { return }
        cancelSequence(owner: owner)
        let sequenceID = makeID()
        var tasks: [any WatchCueCancellable] = []
        for offset in offsets {
            tasks.append(scheduler.schedule(after: offset) { [weak self] in
                guard let self, self.sequences[owner]?.id == sequenceID else { return }
                self.start(.warning, owner: owner)
            })
        }
        sequences[owner] = Sequence(id: sequenceID, tasks: tasks)
    }

    public func stop(owner: UUID) {
        cancelSequence(owner: owner)
        for (id, entry) in playing where entry.owner == owner { stopAndRetire(id) }
    }

    /// Sounds were switched off, or the session was invalidated.
    public func cancelAllWorkoutBells() {
        for owner in Array(sequences.keys) { cancelSequence(owner: owner) }
        for id in Array(playing.keys) { stopAndRetire(id) }
    }

    private func start(_ kind: WatchBellKind, owner: UUID) {
        guard let lease = try? audio.acquire(owner: owner) else { return }
        let id = makeID()
        // Register before starting so a synchronous failure or completion is safe.
        playing[id] = Playing(owner: owner, lease: lease)
        if !driver.start(id: id, kind: kind) { stopAndRetire(id) }
    }

    private func cancelSequence(owner: UUID) {
        sequences.removeValue(forKey: owner)?.tasks.forEach { $0.cancel() }
    }

    private func stopAndRetire(_ id: UUID) {
        guard playing[id] != nil else { return }
        driver.stop(id: id)
        retire(id)
    }

    private func retire(_ id: UUID) {
        guard let entry = playing.removeValue(forKey: id) else { return }
        audio.release(entry.lease)
    }
}
