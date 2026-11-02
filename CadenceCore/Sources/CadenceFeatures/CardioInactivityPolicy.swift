import Foundation

/// Who paused a live cardio/interval workout.
public enum CardioPauseOrigin: String, Codable, Sendable, Equatable {
    case manual, automatic
}

/// Which sensors the session can actually provide. Chosen by the owner at start.
///
/// - `outdoor`: GPS/workout-session distance and motion are preferred evidence; fresh
///   qualifying HR and explicit user action also count.
/// - `indoor`: no GPS; explicit user action plus fresh qualifying HR are evidence
///   (motion/distance are ignored because they are unreliable on a treadmill/bike).
/// - `timerOnly`: no usable sensors; only explicit user action counts, so the conservative
///   timer fallback applies (the automatic pause is visible and reversible).
public enum CardioSensorProfile: String, Codable, Sendable, Equatable {
    case outdoor, indoor, timerOnly
}

/// Value-only evidence. Passive events (UI redraw, screen wake, foregrounding, HealthKit or
/// WatchConnectivity packet receipt, timer ticks, GPS authorization callbacks, duplicate
/// samples) must never be recorded into these fields.
public struct CardioActivityEvidence: Codable, Sendable, Equatable {
    public var lastUserActionAt: Date?
    public var lastDistanceProgressAt: Date?
    public var lastMotionAt: Date?
    public var lastQualifyingHeartRateAt: Date?
    public var isInPlannedIntervalPhase: Bool
    public var pauseOrigin: CardioPauseOrigin?
    public var autoPausedAt: Date?
    /// Session start / last resume; baseline when no evidence has arrived yet.
    public var referenceStartAt: Date?
    public var sensorProfile: CardioSensorProfile

    public init(lastUserActionAt: Date? = nil, lastDistanceProgressAt: Date? = nil,
                lastMotionAt: Date? = nil, lastQualifyingHeartRateAt: Date? = nil,
                isInPlannedIntervalPhase: Bool = false, pauseOrigin: CardioPauseOrigin? = nil,
                autoPausedAt: Date? = nil, referenceStartAt: Date? = nil,
                sensorProfile: CardioSensorProfile = .outdoor) {
        self.lastUserActionAt = lastUserActionAt
        self.lastDistanceProgressAt = lastDistanceProgressAt
        self.lastMotionAt = lastMotionAt
        self.lastQualifyingHeartRateAt = lastQualifyingHeartRateAt
        self.isInPlannedIntervalPhase = isInPlannedIntervalPhase
        self.pauseOrigin = pauseOrigin
        self.autoPausedAt = autoPausedAt
        self.referenceStartAt = referenceStartAt
        self.sensorProfile = sensorProfile
    }

    /// Latest timestamp of evidence that counts for this sensor profile.
    public var lastQualifyingEvidenceAt: Date? {
        let candidates: [Date?]
        switch sensorProfile {
        case .outdoor:
            candidates = [lastUserActionAt, lastDistanceProgressAt, lastMotionAt, lastQualifyingHeartRateAt, referenceStartAt]
        case .indoor:
            candidates = [lastUserActionAt, lastQualifyingHeartRateAt, referenceStartAt]
        case .timerOnly:
            candidates = [lastUserActionAt, referenceStartAt]
        }
        return candidates.compactMap { $0 }.max()
    }
}

public enum CardioInactivityDecision: Sendable, Equatable {
    case continueRunning
    case autoPause(at: Date)
    case continuePaused
    case autoEnd(at: Date)
}

/// Durable, backward-compatible metadata for platform owners (all fields optional).
public struct CardioInactivityState: Codable, Sendable, Equatable {
    public var lastQualifyingActivityAt: Date?
    public var pauseOrigin: CardioPauseOrigin?
    public var pausedAt: Date?
    public var autoEndReason: String?
    public var autoEndDeadline: Date?

    public init(lastQualifyingActivityAt: Date? = nil, pauseOrigin: CardioPauseOrigin? = nil,
                pausedAt: Date? = nil, autoEndReason: String? = nil, autoEndDeadline: Date? = nil) {
        self.lastQualifyingActivityAt = lastQualifyingActivityAt
        self.pauseOrigin = pauseOrigin
        self.pausedAt = pausedAt
        self.autoEndReason = autoEndReason
        self.autoEndDeadline = autoEndDeadline
    }

    public static let autoEndReasonText = "Automatically ended: paused for inactivity and not resumed"

    public mutating func recordAutoPause(at date: Date) {
        pauseOrigin = .automatic
        pausedAt = date
        autoEndDeadline = CardioInactivityPolicy.terminalDeadline(autoPausedAt: date)
        autoEndReason = nil
    }

    public mutating func recordManualPause(at date: Date) {
        pauseOrigin = .manual
        pausedAt = date
        autoEndDeadline = nil
        autoEndReason = nil
    }

    /// A user resume clears the terminal deadline and the automatic-pause state.
    public mutating func recordResume(at date: Date) {
        pauseOrigin = nil
        pausedAt = nil
        autoEndDeadline = nil
        lastQualifyingActivityAt = date
    }

    public mutating func recordAutoEnd(at deadline: Date) {
        autoEndReason = Self.autoEndReasonText
        autoEndDeadline = deadline
    }
}

/// Pure, platform-neutral inactivity policy for live **cardio and interval** workouts.
///
/// 1. After `runningTimeout` (10 min) without qualifying evidence the workout is auto-paused
///    (recording and the underlying session, where supported) at the exact deadline.
/// 2. An unanswered automatic pause auto-ends `automaticPauseGrace` (30 min) after the pause;
///    persisted duration excludes the paused interval (end time = terminal deadline, the
///    owner subtracts `autoPausedAt...end`).
/// 3. Manual pause never auto-ends. Planned interval phases (work or rest) never act.
///
/// Evidence thresholds: outdoor → distance/motion preferred (progress means real movement,
/// not a GPS callback); HR counts only via `isQualifyingHeartRate` (fresh, above 50% of max
/// HR and ≥20 bpm over resting, never a replay); indoor → user action + qualifying HR;
/// no sensors → user action only (timer fallback). Passive events are never evidence.
/// No HealthKit, SwiftUI, WatchConnectivity or timer dependency; time is injected.
public enum CardioInactivityPolicy {
    public static let runningTimeout: TimeInterval = 10 * 60
    public static let automaticPauseGrace: TimeInterval = 30 * 60
    public static let heartRateFreshness: TimeInterval = 60
    public static let defaultMaxHeartRate: Double = 185
    public static let minimumFractionOfMaxHeartRate: Double = 0.5
    public static let minimumAboveResting: Double = 20

    public static func terminalDeadline(autoPausedAt: Date) -> Date {
        autoPausedAt.addingTimeInterval(automaticPauseGrace)
    }

    /// Whether a heart-rate sample is activity evidence. Stale, low, or replayed (not newer
    /// than the last accepted sample) samples do not qualify; neither do relay heartbeats
    /// (they carry no sample time).
    public static func isQualifyingHeartRate(bpm: Double, sampleAt: Date, receivedAt: Date,
                                             previousQualifyingAt: Date?,
                                             restingHeartRate: Double? = nil,
                                             maxHeartRate: Double? = nil) -> Bool {
        guard receivedAt.timeIntervalSince(sampleAt) <= heartRateFreshness,
              sampleAt <= receivedAt.addingTimeInterval(heartRateFreshness) else { return false }
        if let prev = previousQualifyingAt, sampleAt <= prev { return false }
        let maxHR = maxHeartRate ?? defaultMaxHeartRate
        guard bpm >= maxHR * minimumFractionOfMaxHeartRate else { return false }
        if let rest = restingHeartRate, bpm < rest + minimumAboveResting { return false }
        return true
    }

    public static func decide(evidence: CardioActivityEvidence, now: Date,
                              enabled: Bool) -> CardioInactivityDecision {
        switch evidence.pauseOrigin {
        case .manual:
            return .continuePaused
        case .automatic:
            guard enabled, let pausedAt = evidence.autoPausedAt else { return .continuePaused }
            let deadline = terminalDeadline(autoPausedAt: pausedAt)
            return now >= deadline ? .autoEnd(at: deadline) : .continuePaused
        case nil:
            guard enabled, !evidence.isInPlannedIntervalPhase,
                  let last = evidence.lastQualifyingEvidenceAt else { return .continueRunning }
            let deadline = last.addingTimeInterval(runningTimeout)
            return now >= deadline ? .autoPause(at: deadline) : .continueRunning
        }
    }
}
