import Foundation
@testable import CadenceFeatures

@MainActor
final class FakeSessionDriver: WatchCueSessionDriving {
    enum Event: Equatable { case configureMixing, activate, deactivateNotify }
    var events: [Event] = []
    var activateError: Error?
    var deactivateErrors: [Error] = []
    func activateMixingPlayback() throws {
        if let activateError { throw activateError }
        events += [.configureMixing, .activate]
    }
    func deactivateNotifyingOthers() throws {
        events.append(.deactivateNotify)
        if !deactivateErrors.isEmpty { throw deactivateErrors.removeFirst() }
    }
}

@MainActor
final class ManualScheduler: WatchCueScheduling {
    final class Task: WatchCueCancellable {
        let due: TimeInterval
        let work: @MainActor @Sendable () -> Void
        var cancelled = false
        init(due: TimeInterval, work: @escaping @MainActor @Sendable () -> Void) { self.due = due; self.work = work }
        func cancel() { cancelled = true }
    }
    private(set) var now: TimeInterval = 0
    private(set) var tasks: [Task] = []
    var scheduledOffsets: [TimeInterval] { tasks.map(\.due) }
    func schedule(after seconds: TimeInterval,
                  _ work: @escaping @MainActor @Sendable () -> Void) -> any WatchCueCancellable {
        let task = Task(due: now + seconds, work: work)
        tasks.append(task)
        return task
    }
    func advance(_ seconds: TimeInterval) {
        now += seconds
        for task in tasks.sorted(by: { $0.due < $1.due }) where task.due <= now && !task.cancelled {
            task.cancelled = true
            task.work()
        }
    }
    /// Runs one task regardless of cancellation, simulating a stale closure.
    func forceRun(_ index: Int) { tasks[index].work() }
}

@MainActor
final class FakeSpeechDriver: WatchCueSpeechDriving {
    var onEvent: (@MainActor @Sendable (WatchSpeechEvent) -> Void)?
    var enqueued: [(UUID, String)] = []
    var cancelled: [UUID] = []
    var resets = 0
    func enqueue(id: UUID, text: String) { enqueued.append((id, text)) }
    func cancel(id: UUID) { cancelled.append(id) }
    func reset() { resets += 1 }
    func emit(_ event: WatchSpeechEvent) { onEvent?(event) }
}

@MainActor
final class FakeBellDriver: WatchCueBellDriving {
    var onEvent: (@MainActor @Sendable (WatchBellEvent) -> Void)?
    var started: [UUID] = []
    var stopped: [UUID] = []
    var assetAvailable = true
    func start(id: UUID, kind: WatchBellKind) -> Bool {
        guard assetAvailable else { return false }
        started.append(id)
        return true
    }
    func stop(id: UUID) { stopped.append(id) }
    func emit(_ event: WatchBellEvent) { onEvent?(event) }
}

@MainActor
final class WatchCueAudioFixture {
    let session = FakeSessionDriver()
    let scheduler = ManualScheduler()
    let speechDriver = FakeSpeechDriver()
    let bellDriver = FakeBellDriver()
    let audio: WatchCueAudioCoordinator
    let speech: WatchCueSpeechController
    let bells: WatchCueBellController
    let ownerA = UUID()
    let ownerB = UUID()
    var clock = Date(timeIntervalSince1970: 1_000)

    init() {
        audio = WatchCueAudioCoordinator(driver: session, scheduler: scheduler)
        let box = ClockBox()
        speech = WatchCueSpeechController(audio: audio, driver: speechDriver, scheduler: scheduler,
                                          now: { box.value })
        bells = WatchCueBellController(audio: audio, driver: bellDriver, scheduler: scheduler)
        self.box = box
    }
    private let box: ClockBox

    func advanceClock(_ seconds: TimeInterval) { box.value.addTimeInterval(seconds); scheduler.advance(seconds) }

    @discardableResult
    func speak(_ id: String, owner: UUID, enabled: Bool = true) -> UUID? {
        let before = speechDriver.enqueued.count
        speech.speak(eventID: id, text: id, owner: owner, enabled: enabled)
        return speechDriver.enqueued.count > before ? speechDriver.enqueued.last?.0 : nil
    }

    @discardableResult
    func bell(owner: UUID) -> UUID? {
        let before = bellDriver.started.count
        bells.play(.phase, owner: owner, enabled: true)
        return bellDriver.started.count > before ? bellDriver.started.last : nil
    }
}

@MainActor
final class ClockBox { var value = Date(timeIntervalSince1970: 1_000) }
