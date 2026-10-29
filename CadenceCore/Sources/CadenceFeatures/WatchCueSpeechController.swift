import Foundation

public enum WatchSpeechEvent: Sendable, Equatable {
    case started(UUID)
    case finished(UUID)
    case cancelled(UUID)
    case failed(UUID)
}

@MainActor
public protocol WatchCueSpeechDriving: AnyObject {
    var onEvent: (@MainActor @Sendable (WatchSpeechEvent) -> Void)? { get set }
    func enqueue(id: UUID, text: String)
    /// Synchronously stops the engine for this request; later callbacks for it are ignored.
    func cancel(id: UUID)
    /// Drops every concrete speech object after a media-services reset.
    func reset()
}

/// Lifecycle of spoken workout cues: one lease per utterance, retired exactly once.
@MainActor
public final class WatchCueSpeechController {
    private struct Pending {
        let owner: UUID
        let lease: WatchCueLease
        var startDeadline: (any WatchCueCancellable)?
    }

    private let audio: WatchCueAudioCoordinator
    private let driver: any WatchCueSpeechDriving
    private let scheduler: any WatchCueScheduling
    private let now: @MainActor () -> Date
    private let makeID: @MainActor () -> UUID
    private let startTimeout: TimeInterval
    private let dedupInterval: TimeInterval
    private var pending: [UUID: Pending] = [:]
    private var lastEventID: String?
    private var lastSpokenAt = Date.distantPast

    public var pendingCount: Int { pending.count }

    public init(audio: WatchCueAudioCoordinator, driver: any WatchCueSpeechDriving,
                scheduler: any WatchCueScheduling, startTimeout: TimeInterval = 10,
                dedupInterval: TimeInterval = 1,
                now: @escaping @MainActor () -> Date = { Date() },
                makeID: @escaping @MainActor () -> UUID = { UUID() }) {
        self.audio = audio
        self.driver = driver
        self.scheduler = scheduler
        self.startTimeout = startTimeout
        self.dedupInterval = dedupInterval
        self.now = now
        self.makeID = makeID
        driver.onEvent = { [weak self] event in self?.handle(event) }
        audio.addInvalidationHandler { [weak self] reason in
            self?.cancelAllWorkoutSpeech()
            if reason == .mediaReset { self?.driver.reset() }
        }
    }

    public func speak(_ cue: WatchVoiceCue, owner: UUID, enabled: Bool) {
        speak(eventID: cue.eventID, text: cue.speechText, owner: owner, enabled: enabled)
    }

    public func speak(eventID: String, text: String, owner: UUID, enabled: Bool) {
        guard enabled else { return }
        let time = now()
        // TimelineView can deliver the same boundary more than once.
        guard eventID != lastEventID || time.timeIntervalSince(lastSpokenAt) > dedupInterval else { return }
        // Acquire the new reservation before retiring the old one so the session never toggles.
        guard let lease = try? audio.acquire(owner: owner) else { return }
        lastEventID = eventID
        lastSpokenAt = time
        let replaced = Array(pending.keys)
        let id = makeID()
        pending[id] = Pending(owner: owner, lease: lease, startDeadline: scheduleWatchdog(id))
        for old in replaced { driver.cancel(id: old); retire(old) }
        driver.enqueue(id: id, text: text)
    }

    public func stop(owner: UUID) {
        for (id, entry) in pending where entry.owner == owner { driver.cancel(id: id); retire(id) }
        lastEventID = nil
    }

    /// Spoken cues were switched off, or the session was invalidated.
    public func cancelAllWorkoutSpeech() {
        for id in Array(pending.keys) { driver.cancel(id: id); retire(id) }
        lastEventID = nil
    }

    private func scheduleWatchdog(_ id: UUID) -> any WatchCueCancellable {
        scheduler.schedule(after: startTimeout) { [weak self] in
            guard let self, self.pending[id] != nil else { return }
            self.driver.cancel(id: id)
            self.retire(id)
            // Allow the same event to be retried after a start failure.
            self.lastEventID = nil
        }
    }

    private func handle(_ event: WatchSpeechEvent) {
        switch event {
        case .started(let id): pending[id]?.startDeadline?.cancel(); pending[id]?.startDeadline = nil
        case .finished(let id), .cancelled(let id): retire(id)
        case .failed(let id): retire(id); lastEventID = nil
        }
    }

    private func retire(_ id: UUID) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.startDeadline?.cancel()
        audio.release(entry.lease)
    }
}
