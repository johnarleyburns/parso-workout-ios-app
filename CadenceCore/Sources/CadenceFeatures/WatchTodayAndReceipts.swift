import Foundation
import CadenceCore

// Watch redesign (plans/watch-redesign/2026-09-30/DESIGN.md §5 T1–T4, F2, §7): the Today hero, the
// per-destination save receipts, and the learned cardio tile order. Pure; the watch maps them.

/// What leads the watch's Today screen.
public enum WatchTodayHero: Equatable, Sendable {
    /// An unfinished watch workout (T2): title and "Bench done · OHP 2 of 4 sets".
    case resume(title: String, detail: String, startedAt: Date)
    /// Today's planned strength session (T1).
    case planned(sessionID: String, title: String, exercises: [String], minutes: Int?,
                 advice: WatchCoachLine?)
    /// Today's planned cardio (T1 for cardio).
    case plannedCardio(sessionID: String, title: String, detail: String, advice: WatchCoachLine?)
    /// A rest day (T3). `advice` is the coach's own note with its citations, when there is one.
    case restDay(advice: WatchCoachLine?)
    /// Nothing planned or synced yet.
    case unplanned(synced: Bool)
}

public enum WatchTodayHeroBuilder {
    public struct ResumeInput: Equatable, Sendable {
        public let title: String
        public let startedAt: Date
        /// Logged working sets per exercise, in workout order.
        public let exercises: [(name: String, sets: Int)]
        /// Planned working sets per exercise name (case-insensitive), when known.
        public let plannedSets: [String: Int]

        public init(title: String, startedAt: Date, exercises: [(name: String, sets: Int)],
                    plannedSets: [String: Int]) {
            self.title = title
            self.startedAt = startedAt
            self.exercises = exercises
            self.plannedSets = plannedSets
        }

        public static func == (lhs: ResumeInput, rhs: ResumeInput) -> Bool {
            lhs.title == rhs.title && lhs.startedAt == rhs.startedAt && lhs.plannedSets == rhs.plannedSets
                && lhs.exercises.map(\.name) == rhs.exercises.map(\.name)
                && lhs.exercises.map(\.sets) == rhs.exercises.map(\.sets)
        }
    }

    public static func make(resume: ResumeInput?, plan: WatchSync.TodayPlan?) -> WatchTodayHero {
        if let resume { return .resume(title: resume.title, detail: resumeDetail(resume), startedAt: resume.startedAt) }
        guard let plan else { return .unplanned(synced: false) }
        if plan.isRestDay {
            return .restDay(advice: plan.sessions.lazy.compactMap(advice).first)
        }
        if let strength = plan.sessions.first(where: \.isStrength) {
            let names = strength.planPayload?.strength?.exerciseNames.nonEmpty ?? strength.exerciseNames
            return .planned(sessionID: strength.id,
                            title: strength.label.isEmpty ? String(localized: "Strength", bundle: .module) : strength.label,
                            exercises: names,
                            minutes: estimatedMinutes(strength),
                            advice: advice(strength))
        }
        if let cardio = plan.sessions.first(where: { $0.kind == .cardio }) {
            var parts: [String] = []
            if let minutes = cardio.durationMinutes { parts.append(String(localized: "\(minutes) min", bundle: .module)) }
            if let zone = cardio.zone { parts.append(String(localized: "Zone \(zone)", bundle: .module)) }
            return .plannedCardio(sessionID: cardio.id,
                                  title: cardio.label.isEmpty ? String(localized: "Cardio", bundle: .module) : cardio.label,
                                  detail: parts.joined(separator: " · "), advice: advice(cardio))
        }
        return .unplanned(synced: true)
    }

    /// "Bench done · OHP 2 of 4 sets" — finished exercises collapse; the current one shows progress.
    static func resumeDetail(_ resume: ResumeInput) -> String {
        guard let current = resume.exercises.last else {
            return String(localized: "No sets logged yet", bundle: .module)
        }
        let finished = resume.exercises.dropLast().map {
            String(localized: "\($0.name) done", bundle: .module)
        }
        let planned = resume.plannedSets.first { $0.key.caseInsensitiveCompare(current.name) == .orderedSame }?.value
        let progress = planned.map { String(localized: "\(current.name) \(current.sets) of \($0)", bundle: .module) }
            ?? String(localized: "\(current.name) · \(current.sets) logged", bundle: .module)
        return (finished.suffix(1) + [progress]).joined(separator: " · ")
    }

    /// Same constants as `WorkoutDurationEstimator` (40 s work + 90 s rest per set). Unknown when the
    /// plan doesn't say how many sets — never a guess.
    static func estimatedMinutes(_ session: WatchSync.TodayPlan.Session) -> Int? {
        let sets = session.planPayload?.strength?.prescriptions.reduce(0) { $0 + $1.sets.count } ?? 0
        guard sets > 0 else { return nil }
        let seconds = Double(sets) * (WorkoutDurationEstimator.defaultWorkSeconds + WorkoutDurationEstimator.defaultRestSeconds)
        return max(1, Int((seconds / 60).rounded()))
    }

    static func advice(_ session: WatchSync.TodayPlan.Session) -> WatchCoachLine? {
        guard let note = session.adviceNote, !note.isEmpty else { return nil }
        return WatchCoachLine(text: note, citationIDs: session.adviceCitationIDs)
    }
}

/// The save receipts after Finish (F2): one row per destination, each with its real state.
public struct WatchSaveReceipt: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case done
        case inProgress(String)
        case waiting(String)
        case failed(String)
    }

    public let watch: State
    public let iPhone: State
    public let health: State

    /// - Parameters:
    ///   - pendingTransfers: WatchConnectivity user-info transfers still queued for this workout.
    ///   - phoneReachable: whether the iPhone is reachable right now.
    ///   - transferError: the last transfer error, if one was reported.
    public static func make(savedOnWatch: Bool, pendingTransfers: Int, phoneReachable: Bool,
                            transferError: String?) -> WatchSaveReceipt {
        let watch: State = savedOnWatch ? .done : .failed(String(localized: "Not saved", bundle: .module))
        let phone: State
        if let transferError {
            phone = .failed(transferError)
        } else if pendingTransfers == 0 {
            phone = .done
        } else if phoneReachable {
            phone = .inProgress(String(localized: "Sending to iPhone · \(pendingTransfers) left", bundle: .module))
        } else {
            phone = .waiting(String(localized: "Sends when your iPhone is nearby", bundle: .module))
        }
        // Strength summaries reach Apple Health from the iPhone once it has the sets.
        let health: State
        switch phone {
        case .done: health = .done
        case .failed: health = .waiting(String(localized: "After iPhone sync", bundle: .module))
        default: health = .waiting(String(localized: "Saved by your iPhone after sync", bundle: .module))
        }
        return WatchSaveReceipt(watch: watch, iPhone: phone, health: health)
    }
}

/// Cardio tiles in learned order (T4): most-started first, ties in catalog order; four tiles.
public enum WatchCardioTileOrder {
    public static func ordered(_ kinds: [String], counts: [String: Int], tiles: Int = 4) -> (tiles: [String], more: [String]) {
        let ranked = kinds.enumerated().sorted { lhs, rhs in
            let l = counts[lhs.element, default: 0], r = counts[rhs.element, default: 0]
            return l != r ? l > r : lhs.offset < rhs.offset
        }.map(\.element)
        return (Array(ranked.prefix(tiles)), Array(ranked.dropFirst(tiles)))
    }
}

private extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}
