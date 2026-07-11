import Foundation

/// A single "run this fitness test" suggestion the coach surfaces at most once a
/// week. Carries the test kind, why it's suggested, and the assessment's own
/// citations (HARD RULE: every coach output is cited).
public struct TestRecommendation: Equatable, Sendable, Identifiable {
    public enum Reason: Equatable, Sendable {
        case neverTested
        case stale(days: Int)
    }

    public let kind: AssessmentKind
    public let reason: Reason
    public let citationIds: [String]

    public var id: String { kind.rawValue }

    public init(kind: AssessmentKind, reason: Reason, citationIds: [String]) {
        self.kind = kind
        self.reason = reason
        self.citationIds = citationIds
    }

    /// A short, user-facing "why now" line.
    public var whyNow: String {
        switch reason {
        case .neverTested:
            return "You haven't run this test yet — a baseline lets Coach track progress and tailor prescriptions."
        case .stale(let days):
            return "Your last result is \(days) days old. Re-testing keeps Coach's baseline current."
        }
    }
}

/// Pure decision logic for *when* and *which* fitness test the coach recommends —
/// no UI, no I/O (issue 11). The app layer owns the persisted state
/// (last-recommended timestamp + per-kind snooze map) and passes it in, mirroring
/// `ContributionPromptEngine`.
///
/// Rules:
///  • At most one test recommendation per `minDaysBetweenRecommendations` (default 7).
///  • Never-tested kinds are prioritized first, then the most-stale due kinds.
///  • A kind the user said "not right now" to is suppressed until its snooze expires.
///  • "Pick a different test" cycles through `candidates` (which ignores the weekly
///    gate) so the user can advance to the next-priority kind within a shown card.
///  • Fresh kinds (tested within the retest cadence) are never recommended.
public enum CoachTestRecommendationEngine {

    public struct Inputs: Sendable {
        /// The battery of test kinds to consider (defaults to the standard
        /// no-lab battery — excludes advanced tests needing lab gear).
        public var battery: [AssessmentKind]
        /// Existing test results, one summary per series.
        public var summaries: [AssessmentSummary]
        /// When the coach last surfaced *any* test recommendation.
        public var lastRecommendedAt: Date?
        /// Per-kind snooze expiry (`AssessmentKind.rawValue` → date). A kind is
        /// suppressed while `now < snoozedUntil[kind]`.
        public var snoozedUntil: [String: Date]
        public var minDaysBetweenRecommendations: Double
        public var retestCadenceDays: Int
        public var now: Date

        public init(battery: [AssessmentKind] = AssessmentKind.defaultBattery,
                    summaries: [AssessmentSummary],
                    lastRecommendedAt: Date? = nil,
                    snoozedUntil: [String: Date] = [:],
                    minDaysBetweenRecommendations: Double = 7,
                    retestCadenceDays: Int = AssessmentMath.defaultRetestDays,
                    now: Date = Date()) {
            self.battery = battery
            self.summaries = summaries
            self.lastRecommendedAt = lastRecommendedAt
            self.snoozedUntil = snoozedUntil
            self.minDaysBetweenRecommendations = minDaysBetweenRecommendations
            self.retestCadenceDays = retestCadenceDays
            self.now = now
        }
    }

    /// The prioritized candidate list, never-tested first then most-stale,
    /// excluding fresh and currently-snoozed kinds. Ignores the weekly gate so
    /// "pick a different test" can cycle within an already-shown card.
    public static func candidates(_ i: Inputs) -> [TestRecommendation] {
        let summaryByKind = Dictionary(
            i.summaries.map { ($0.kind, $0) },
            uniquingKeysWith: { a, b in a.latestDate >= b.latestDate ? a : b })

        var neverTested: [TestRecommendation] = []
        var stale: [(rec: TestRecommendation, days: Int)] = []

        for kind in i.battery {
            // Respect an active snooze ("not right now" / dismissed).
            if let until = i.snoozedUntil[kind.rawValue], i.now < until { continue }

            guard let summary = summaryByKind[kind] else {
                neverTested.append(TestRecommendation(
                    kind: kind, reason: .neverTested, citationIds: kind.citationIds))
                continue
            }
            let days = summary.daysSinceLatest(now: i.now)
            guard days >= i.retestCadenceDays else { continue }   // still fresh
            stale.append((TestRecommendation(kind: kind, reason: .stale(days: days),
                                             citationIds: kind.citationIds), days))
        }

        // Most-stale first; ties broken by battery order for determinism.
        let staleSorted = stale
            .enumerated()
            .sorted { a, b in
                if a.element.days != b.element.days { return a.element.days > b.element.days }
                return a.offset < b.offset
            }
            .map(\.element.rec)

        return neverTested + staleSorted
    }

    /// The single test recommendation to show this week, or nil if the weekly gate
    /// is closed or there is nothing due.
    public static func recommendation(_ i: Inputs) -> TestRecommendation? {
        if let last = i.lastRecommendedAt {
            let daysSince = i.now.timeIntervalSince(last) / 86_400
            if daysSince < i.minDaysBetweenRecommendations { return nil }
        }
        return candidates(i).first
    }
}
