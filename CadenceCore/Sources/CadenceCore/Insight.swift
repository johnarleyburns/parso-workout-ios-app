import Foundation

/// How prominently an insight should surface. `attention` outranks `info` on the
/// Coach card and in the ranked list.
public enum InsightSeverity: Int, Sendable, Equatable, Comparable {
    case info
    case attention
    public static func < (lhs: InsightSeverity, rhs: InsightSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The rule family an insight came from (drives the leading SF Symbol / grouping).
public enum InsightKind: String, Sendable, Equatable {
    case volume
    case trend
    case frequency
    case intensity
    case assessment
    case coldStart
    case exerciseDefinition
}

/// A single read-only coaching observation derived from `TrainingFacts`. This is
/// the P3 form of the engine's `Recommendation` (§03): it describes what the data
/// shows and *why it matters*, with a mandatory citation (decision D3). Prescriptive
/// actions (load/sets/RIR targets) are added in P5; there are none here.
public struct Insight: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: InsightKind
    public let part: BodyPart?      // the body part this concerns, if any
    public let exercise: String?    // the lift this concerns, if any
    public let title: String        // short headline, e.g. "Chest volume is low"
    public let message: String      // one-line takeaway shown on the card
    public let detail: String       // the "why / the science" expansion
    public let citation: Citation   // always present (D3)
    public let severity: InsightSeverity

    public init(id: String,
                kind: InsightKind,
                part: BodyPart? = nil,
                exercise: String? = nil,
                title: String,
                message: String,
                detail: String,
                citation: Citation,
                severity: InsightSeverity) {
        self.id = id
        self.kind = kind
        self.part = part
        self.exercise = exercise
        self.title = title
        self.message = message
        self.detail = detail
        self.citation = citation
        self.severity = severity
    }
}
