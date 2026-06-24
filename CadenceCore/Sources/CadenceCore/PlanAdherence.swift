import Foundation

public enum PlanAdherence: Sendable, Equatable {
    case planAhead
    case planComplete(completedKind: CoachSessionKind?,
                      todayDescription: String,
                      tomorrowPreview: String?)
    case offPlan(didSomethingToday: Bool)
}

/// A claim Coach makes, with a pool of citations that rotate deterministically.
public struct EvidenceClaim: Sendable, Equatable {
    public let id: String
    public let text: String
    public let policyNote: String?
    public let poolId: String
    public let selectedCitationId: String

    public init(id: String, text: String, policyNote: String? = nil,
                poolId: String, selectedCitationId: String) {
        self.id = id
        self.text = text
        self.policyNote = policyNote
        self.poolId = poolId
        self.selectedCitationId = selectedCitationId
    }
}

/// A pool of citation IDs that can be rotated for variety.
public struct CitationPool: Sendable, Equatable {
    public let id: String
    public let citationIds: [String]

    public init(id: String, citationIds: [String]) {
        self.id = id
        self.citationIds = citationIds
    }

    public func select(for date: Date, stableId: String) -> String? {
        guard !citationIds.isEmpty else { return nil }
        let cal = Calendar.current
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: date) ?? 0
        let hash = abs(stableId.hashValue)
        let index = (dayOfYear + hash) % citationIds.count
        return citationIds[index]
    }
}
