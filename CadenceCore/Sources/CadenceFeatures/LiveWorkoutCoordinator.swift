import Foundation
import Observation
import CadenceCore

public enum LiveWorkoutKind: Equatable, Sendable {
    case strength(sessionID: UUID)
    case combinedPlan(id: UUID)
    case outdoorCardio(id: UUID, type: CardioType)
    case timerCardio(id: UUID, type: CardioType)
    case interval(id: UUID, type: CardioType)
    case swim(id: UUID)
}

public struct LiveWorkoutDescriptor: Equatable, Sendable {
    public let kind: LiveWorkoutKind
    public let name: String
    public let startedAt: Date
    public init(kind: LiveWorkoutKind, name: String, startedAt: Date = Date()) {
        self.kind = kind; self.name = name; self.startedAt = startedAt
    }
}

public struct LiveWorkoutStartIntent: Equatable, Sendable, Identifiable {
    public enum Origin: String, Sendable { case homeStart, finalCommit, plan, history, coach, quickStart, recovery }
    public let id: UUID
    public let kind: LiveWorkoutKind
    public let routePayload: String
    public let origin: Origin
    public init(id: UUID = UUID(), kind: LiveWorkoutKind, routePayload: String = "", origin: Origin) {
        self.id = id; self.kind = kind; self.routePayload = routePayload; self.origin = origin
    }
}

public struct LiveWorkoutLease: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let intentID: UUID
    public let kind: LiveWorkoutKind
    public init(id: UUID = UUID(), intentID: UUID, kind: LiveWorkoutKind) {
        self.id = id; self.intentID = intentID; self.kind = kind
    }
}

public enum AtomicWorkoutStartDecision: Equatable, Sendable {
    case granted(LiveWorkoutLease)
    case conflict(active: LiveWorkoutDescriptor, pending: LiveWorkoutStartIntent)
}

public enum WorkoutStartDecision: Equatable, Sendable {
    case allowed
    case conflict(active: LiveWorkoutDescriptor)
}

/// The root-owned lease for every live recorder. It deliberately does not use
/// presentation state as liveness: dismissing a sheet cannot orphan a sensor or
/// allow a second workout to start.
@MainActor @Observable
public final class LiveWorkoutCoordinator {
    public private(set) var active: LiveWorkoutDescriptor?
    public private(set) var pending: LiveWorkoutKind?
    public private(set) var pendingIntent: LiveWorkoutStartIntent?
    public private(set) var lease: LiveWorkoutLease?

    public init() {}

    /// Atomically reserves the only live-workout slot. Callers must not create a
    /// session or start a recorder until this operation returns a lease.
    public func requestStart(intent: LiveWorkoutStartIntent,
                             descriptorName: String = "Workout",
                             startedAt: Date = Date()) -> AtomicWorkoutStartDecision {
        if let active {
            pendingIntent = intent
            pending = intent.kind
            return .conflict(active: active, pending: intent)
        }
        let descriptor = LiveWorkoutDescriptor(kind: intent.kind, name: descriptorName, startedAt: startedAt)
        let newLease = LiveWorkoutLease(intentID: intent.id, kind: intent.kind)
        active = descriptor
        lease = newLease
        pending = nil
        pendingIntent = nil
        return .granted(newLease)
    }

    @discardableResult
    public func release(_ lease: LiveWorkoutLease) -> Bool {
        guard self.lease == lease else { return false }
        self.lease = nil
        active = nil
        return true
    }

    public func clearPending(intentID: UUID) {
        guard pendingIntent?.id == intentID else { return }
        pendingIntent = nil; pending = nil
    }

    /// Replaces the pre-start descriptor with the concrete recorder identity
    /// without releasing the lease or reopening the race window.
    @discardableResult
    public func adopt(_ lease: LiveWorkoutLease, descriptor: LiveWorkoutDescriptor) -> Bool {
        guard self.lease == lease, active != nil else { return false }
        active = descriptor
        return true
    }

    public func requestStart(_ kind: LiveWorkoutKind) -> WorkoutStartDecision {
        if let active { pending = kind; return .conflict(active: active) }
        return .allowed
    }

    @discardableResult
    public func acquire(_ descriptor: LiveWorkoutDescriptor) -> Bool {
        guard active == nil else { return false }
        active = descriptor
        lease = LiveWorkoutLease(intentID: UUID(), kind: descriptor.kind)
        pending = nil
        pendingIntent = nil
        return true
    }

    public func resumeAndClearPending() { pending = nil; pendingIntent = nil }
    public func cancelPending() { pending = nil; pendingIntent = nil }

    public func release(kind: LiveWorkoutKind? = nil) -> Bool {
        guard let active, kind == nil || active.kind == kind else { return false }
        self.active = nil
        self.lease = nil
        return true
    }

    public func replaceAfterCleanup(_ descriptor: LiveWorkoutDescriptor) -> Bool {
        guard active == nil else { return false }
        active = descriptor
        lease = LiveWorkoutLease(intentID: UUID(), kind: descriptor.kind)
        pending = nil
        pendingIntent = nil
        return true
    }
}
