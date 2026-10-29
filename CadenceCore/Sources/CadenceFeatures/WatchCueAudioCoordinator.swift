import Foundation
import OSLog

/// Identity-carrying claim on the shared cue audio session. Released exactly once.
public struct WatchCueLease: Hashable, Sendable {
    public let id: UUID
    public let owner: UUID
    public let epoch: UInt64
}

public enum CueAudioError: Error, Equatable, Sendable {
    case interrupted
}

/// Session failures the coordinator must classify. `busy` means the system reported
/// `isBusy` while still deactivating, so it is treated as released.
public enum WatchCueSessionError: Error, Equatable, Sendable {
    case busy
    case failed(domain: String, code: Int)
}

@MainActor
public protocol WatchCueSessionDriving: AnyObject {
    func activateMixingPlayback() throws
    func deactivateNotifyingOthers() throws
}

public protocol WatchCueCancellable: AnyObject {
    func cancel()
}

@MainActor
public protocol WatchCueScheduling: AnyObject {
    func schedule(after seconds: TimeInterval,
                  _ work: @escaping @MainActor @Sendable () -> Void) -> any WatchCueCancellable
}

public enum WatchCueInvalidation: Sendable, Equatable {
    case interruption, routeLoss, mediaReset
}

public enum WatchCueSessionState: Sendable, Equatable {
    case inactive, active, interrupted, uncertain
}

/// The single owner of the app playback session for Watch cues. Speech and bells hold
/// independent leases; the session is configured on the first lease and released after the last.
@MainActor
public final class WatchCueAudioCoordinator {
    public private(set) var state: WatchCueSessionState = .inactive
    public private(set) var epoch: UInt64 = 0
    public var activeLeaseCount: Int { leases.count }

    private var leases: Set<WatchCueLease> = []
    private var invalidationHandlers: [@MainActor (WatchCueInvalidation) -> Void] = []
    private var retry: (any WatchCueCancellable)?
    private let driver: any WatchCueSessionDriving
    private let scheduler: any WatchCueScheduling
    private let makeID: @MainActor () -> UUID
    private let retryDelay: TimeInterval
    private let log = Logger(subsystem: "guru.parso.cladiron", category: "watch-cue-audio")

    public init(driver: any WatchCueSessionDriving, scheduler: any WatchCueScheduling,
                retryDelay: TimeInterval = 2, makeID: @escaping @MainActor () -> UUID = { UUID() }) {
        self.driver = driver
        self.scheduler = scheduler
        self.retryDelay = retryDelay
        self.makeID = makeID
    }

    /// Adapters register to stop all their playback and queued work on a process-level invalidation.
    public func addInvalidationHandler(_ handler: @escaping @MainActor (WatchCueInvalidation) -> Void) {
        invalidationHandlers.append(handler)
    }

    public func acquire(owner: UUID) throws -> WatchCueLease {
        guard state != .interrupted else { throw CueAudioError.interrupted }
        retry?.cancel()
        retry = nil
        if leases.isEmpty {
            do {
                try driver.activateMixingPlayback()
                state = .active
            } catch {
                state = .uncertain
                log.error("cue session activation failed \(Self.describe(error), privacy: .public)")
                throw error
            }
        }
        let lease = WatchCueLease(id: makeID(), owner: owner, epoch: epoch)
        leases.insert(lease)
        log.debug("acquire owners=\(self.leases.count, privacy: .public) epoch=\(self.epoch, privacy: .public)")
        return lease
    }

    public func release(_ lease: WatchCueLease) {
        guard leases.remove(lease) != nil else { return }
        log.debug("release owners=\(self.leases.count, privacy: .public)")
        guard leases.isEmpty, state != .interrupted else { return }
        deactivate(allowRetry: true)
    }

    /// Stops every adapter, forgets every lease and invalidates late callbacks.
    public func invalidateAll(_ reason: WatchCueInvalidation) {
        epoch &+= 1
        retry?.cancel()
        retry = nil
        leases.removeAll()
        for handler in invalidationHandlers { handler(reason) }
        log.notice("cue audio invalidated \(String(describing: reason), privacy: .public)")
        switch reason {
        case .interruption: state = .interrupted
        case .routeLoss: deactivate(allowRetry: true)
        case .mediaReset: state = .inactive
        }
    }

    public func interruptionBegan() { invalidateAll(.interruption) }

    /// Never replays; a fresh cue re-activates the session.
    public func interruptionEnded() {
        guard state == .interrupted else { return }
        state = .inactive
    }

    private func deactivate(allowRetry: Bool) {
        do {
            try driver.deactivateNotifyingOthers()
            state = .inactive
        } catch WatchCueSessionError.busy {
            state = .inactive
        } catch {
            state = .uncertain
            log.error("cue session deactivation failed \(Self.describe(error), privacy: .public)")
            if allowRetry { scheduleRetry() }
        }
    }

    /// One bounded, idle-only retry; a newer acquire cancels it.
    private func scheduleRetry() {
        let scheduledEpoch = epoch
        retry = scheduler.schedule(after: retryDelay) { [weak self] in
            guard let self, self.epoch == scheduledEpoch, self.leases.isEmpty,
                  self.state == .uncertain else { return }
            self.retry = nil
            self.deactivate(allowRetry: false)
        }
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain)/\(ns.code)"
    }
}

/// Production scheduler backed by structured main-actor tasks.
@MainActor
public final class WatchCueTaskScheduler: WatchCueScheduling {
    public init() {}

    private final class Handle: WatchCueCancellable {
        var task: Task<Void, Never>?
        func cancel() { task?.cancel() }
    }

    public func schedule(after seconds: TimeInterval,
                         _ work: @escaping @MainActor @Sendable () -> Void) -> any WatchCueCancellable {
        let handle = Handle()
        handle.task = Task { @MainActor in
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard !Task.isCancelled else { return }
            work()
        }
        return handle
    }
}
