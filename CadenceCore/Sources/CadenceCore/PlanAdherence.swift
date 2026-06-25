import Foundation

public enum PlanAdherence: Sendable, Equatable {
    case planAhead
    case planComplete(completedKind: CoachSessionKind?,
                      todayDescription: String,
                      tomorrowPreview: String?)
    case offPlan(didSomethingToday: Bool)
}

/// A claim Coach makes, with a pool of citations that rotate deterministically.
/// As of the 2026-06-25 evidence upgrade a claim also carries a typed
/// `EvidenceClaimCategory` so the citation it shows is guaranteed to come from the
/// pool curated for that claim class.
public struct EvidenceClaim: Sendable, Equatable {
    public let id: String
    public let text: String
    public let policyNote: String?
    public let poolId: String
    public let selectedCitationId: String
    /// The typed claim class. Optional only for legacy call sites that still pass a
    /// raw `poolId`; new code should use the category-based initializer.
    public let category: EvidenceClaimCategory?

    public init(id: String, text: String, policyNote: String? = nil,
                poolId: String, selectedCitationId: String,
                category: EvidenceClaimCategory? = nil) {
        self.id = id
        self.text = text
        self.policyNote = policyNote
        self.poolId = poolId
        self.selectedCitationId = selectedCitationId
        self.category = category
    }

    /// Build a claim from a typed category, deterministically selecting a citation
    /// from that category's pool. This is the preferred path: the citation can only
    /// come from the category's curated pool.
    public init(id: String, text: String, policyNote: String? = nil,
                category: EvidenceClaimCategory, date: Date) {
        let pool = CitationRegistry.citationPool(for: category)
        self.id = id
        self.text = text
        self.policyNote = policyNote
        self.poolId = pool.id
        self.selectedCitationId = pool.select(for: date, stableId: id) ?? (pool.citationIds.first ?? "")
        self.category = category
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
