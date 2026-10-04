import Foundation

/// Decides whether the Watch's running `HKWorkoutSession` still belongs to something the user can
/// see. Field test 2026-10-03: a watch workout that had ended long before was still recording
/// 27 hours later. watchOS keeps a workout session alive across app relaunches, and after a
/// relaunch nothing on screen owned it, so nothing ever ended it.
///
/// A session is owned by a workout screen that is showing, by the iPhone workout that started it,
/// or by an unfinished watch strength workout that Today offers to resume. Anything else is
/// recording for no one: Today shows it with an End button, and once it is clearly abandoned it is
/// ended automatically and Today says so (Transparency HARD RULE).
public enum WatchSessionOwnership {
    public struct Input: Equatable, Sendable {
        public var isRunning: Bool
        public var startedAt: Date?
        public var workoutType: String?
        public var workoutScreenVisible: Bool
        public var ownedByPhone: Bool
        public var hasResumableStrength: Bool

        public init(isRunning: Bool, startedAt: Date?, workoutType: String?,
                    workoutScreenVisible: Bool, ownedByPhone: Bool, hasResumableStrength: Bool) {
            self.isRunning = isRunning
            self.startedAt = startedAt
            self.workoutType = workoutType
            self.workoutScreenVisible = workoutScreenVisible
            self.ownedByPhone = ownedByPhone
            self.hasResumableStrength = hasResumableStrength
        }
    }

    public enum Verdict: Equatable, Sendable {
        /// Nothing to do: no session, or something the user can see owns it.
        case owned
        /// Recording for no one; Today offers to end it.
        case unowned(startedAt: Date)
        /// Abandoned; end it now and tell the user on Today.
        case endNow(startedAt: Date)
    }

    /// An unowned session older than this is ended without asking. Longer than any real
    /// workout left alone between sets, far shorter than the 27 hours seen in the field.
    public static let abandonedAfter: TimeInterval = 4 * 3600
    /// A phone-started session normally ends when the phone's workout does; past this age the
    /// phone's stop has been lost.
    public static let phoneOwnedLimit: TimeInterval = 6 * 3600

    public static func verdict(_ input: Input, now: Date = Date()) -> Verdict {
        guard input.isRunning else { return .owned }
        if input.workoutScreenVisible { return .owned }
        let startedAt = input.startedAt ?? now
        let age = max(0, now.timeIntervalSince(startedAt))
        if input.ownedByPhone { return age < phoneOwnedLimit ? .owned : .endNow(startedAt: startedAt) }
        if age >= abandonedAfter { return .endNow(startedAt: startedAt) }
        if input.hasResumableStrength, input.workoutType == "strength" { return .owned }
        return .unowned(startedAt: startedAt)
    }

    /// For a background relaunch, before any UI or SwiftData query exists: only an abandoned
    /// session can be judged, so only `.endNow` or `.owned` come back.
    public static func backgroundVerdict(startedAt: Date?, ownedByPhone: Bool,
                                         now: Date = Date()) -> Verdict {
        let verdict = verdict(Input(isRunning: true, startedAt: startedAt, workoutType: nil,
                                    workoutScreenVisible: false, ownedByPhone: ownedByPhone,
                                    hasResumableStrength: true), now: now)
        if case .endNow = verdict { return verdict }
        return .owned
    }
}
