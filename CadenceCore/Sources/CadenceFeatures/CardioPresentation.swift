import Foundation
import Observation
import CadenceCore

/// Presentation lifecycle of a live cardio surface (run/walk/cycle/rowing,
/// swim, boxing, HIIT, timer/other). Pure so every modality shares one set of
/// rules: a running workout can never be dismissed; a paused one can be
/// *minimized* (never discarded) and reopened exactly as it was.
public enum CardioPresentationState: Equatable, Sendable {
    case running, paused, minimized, ended
}

public enum CardioPresentationEvent: Equatable, Sendable {
    case pause, resume
    /// Explicit "Return to Today" button or the downward-dismiss gesture.
    case minimize
    case reopen
    case end
}

public struct CardioPresentation: Equatable, Sendable {
    public private(set) var state: CardioPresentationState

    public init(state: CardioPresentationState = .running) { self.state = state }

    /// The state a live surface is in, derived from the authoritative
    /// recorder/clock pause flag so there is no second source of truth.
    public static func live(isPaused: Bool) -> CardioPresentation {
        CardioPresentation(state: isPaused ? .paused : .running)
    }

    public var isPaused: Bool { state == .paused || state == .minimized }

    /// The interactive downward dismissal is allowed only while paused (it
    /// minimizes). While running — or in the summary — it stays disabled so
    /// the gesture can never silently end or lose a live workout.
    public var allowsInteractiveMinimize: Bool { state == .paused }

    public var canMinimize: Bool { state == .paused }

    /// Applies an event; invalid transitions are ignored (idempotent resume,
    /// minimize-while-running is a no-op). Returns whether state changed.
    @discardableResult
    public mutating func apply(_ event: CardioPresentationEvent) -> Bool {
        let next: CardioPresentationState
        switch (state, event) {
        case (.running, .pause): next = .paused
        case (.paused, .resume): next = .running
        case (.paused, .minimize): next = .minimized
        case (.minimized, .reopen): next = .paused
        case (.running, .end), (.paused, .end), (.minimized, .end): next = .ended
        default: return false
        }
        state = next
        return true
    }

    public static let returnToTodayLabel = "Return to Today"
    public static let minimizeHint = "Minimizes the paused workout. It stays paused and is not ended or discarded."
    public static let pausedAnnouncement = "Workout paused. Return to Today is available."
    public static let runningDismissReason = "Pause the workout to return to Today. Dismissing never ends it."
}

/// Which cardio surface a parked session reopens into.
public enum ParkedCardioRoute: Equatable, Sendable {
    case record, outdoor, swim, interval
}

/// A paused, minimized cardio session. Holds the authoritative recorder and
/// clock so reopening restores the exact state; nothing is copied.
public final class ParkedCardioSession {
    public let id = UUID()
    public let route: ParkedCardioRoute
    public let type: CardioType
    public let recorder: CardioRecorder?
    public var clock: WorkoutClock
    public var customTitle: String?
    public var goalMeters: Double?
    public var tracksGPS: Bool?
    public var captureHR: Bool
    /// Swim-only state.
    public var laps: Int
    public var targetLaps: Int
    public var startDate: Date
    /// Interval-only (boxing/HIIT) state: the authoritative runner and samples.
    public var intervalRunner: IntervalRunner?
    public var intervalPlan: IntervalPlan?
    public var hrSamples: [HRSamplePoint]

    public init(route: ParkedCardioRoute, type: CardioType, recorder: CardioRecorder? = nil,
                clock: WorkoutClock = WorkoutClock(), customTitle: String? = nil,
                goalMeters: Double? = nil, tracksGPS: Bool? = nil, captureHR: Bool = false,
                laps: Int = 0, targetLaps: Int = 20, startDate: Date = Date(),
                intervalRunner: IntervalRunner? = nil, intervalPlan: IntervalPlan? = nil,
                hrSamples: [HRSamplePoint] = []) {
        self.route = route; self.type = type; self.recorder = recorder; self.clock = clock
        self.customTitle = customTitle; self.goalMeters = goalMeters; self.tracksGPS = tracksGPS
        self.captureHR = captureHR; self.laps = laps; self.targetLaps = targetLaps
        self.startDate = startDate
        self.intervalRunner = intervalRunner; self.intervalPlan = intervalPlan
        self.hrSamples = hrSamples
    }
}

/// Single slot for the minimized cardio session — at most one, so reopening
/// can never produce a duplicate active session.
@Observable
public final class ParkedCardioStore {
    public private(set) var session: ParkedCardioSession?
    public init() {}

    public var isParked: Bool { session != nil }

    /// Parks a paused session. Refuses a second distinct session.
    @discardableResult
    public func park(_ new: ParkedCardioSession) -> Bool {
        if let session, session !== new { return false }
        session = new
        return true
    }

    /// Hands the session back to the reopening surface and empties the slot.
    public func take() -> ParkedCardioSession? {
        defer { session = nil }
        return session
    }

    /// Drops the slot after End/save (never called by minimize).
    public func clear() { session = nil }
}
