import Foundation

/// Resolves who is "in" a strength session for partner attribution.
///
/// Partners are **opt-in**: an empty `activePartnerIDs` means the user is
/// training solo (just the owner), NOT "show everyone". This is the single
/// source of truth for the session view's roster, the WHO column, and the
/// performer pickers, so "select no partners" and "remove the last partner"
/// both correctly collapse to solo (field-testing §04 bug fix).
public enum SessionRoster {

    /// Partners explicitly scoped to a session, sorted by name. Empty when the
    /// user chose none (solo).
    public static func scopedPartners(activePartnerIDs: [String],
                                      allPeople: [Person]) -> [Person] {
        guard !activePartnerIDs.isEmpty else { return [] }
        let ids = Set(activePartnerIDs.compactMap(UUID.init(uuidString:)))
        return allPeople
            .filter { !$0.isMe && ids.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Owner first, then scoped partners. Solo sessions resolve to just the owner.
    public static func roster(activePartnerIDs: [String],
                              allPeople: [Person]) -> [Person] {
        allPeople.filter(\.isMe)
            + scopedPartners(activePartnerIDs: activePartnerIDs, allPeople: allPeople)
    }

    /// At least one partner is scoped to the session.
    public static func hasPartners(activePartnerIDs: [String],
                                   allPeople: [Person]) -> Bool {
        !scopedPartners(activePartnerIDs: activePartnerIDs, allPeople: allPeople).isEmpty
    }

    /// Partners that may be picked when attributing a set: the scoped partners
    /// PLUS anyone already attributed to a set in the session (so a set
    /// mistakenly attributed to a now-unscoped partner can still be corrected
    /// back to "Me"). Sorted by name, owner excluded (the caller adds "Me").
    public static func attributablePartners(activePartnerIDs: [String],
                                            allPeople: [Person],
                                            includingAttributed attributedIDs: [UUID] = []) -> [Person] {
        var ids = Set(activePartnerIDs.compactMap(UUID.init(uuidString:)))
        ids.formUnion(attributedIDs)
        return allPeople
            .filter { !$0.isMe && ids.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Whether the session can attribute sets to a partner: either a partner is
    /// scoped, or a set is already attributed to one. Drives the WHO column and
    /// the performer pickers (including when editing a past workout).
    public static func canAttribute(activePartnerIDs: [String],
                                    allPeople: [Person],
                                    attributedIDs: [UUID] = []) -> Bool {
        !attributablePartners(activePartnerIDs: activePartnerIDs,
                              allPeople: allPeople,
                              includingAttributed: attributedIDs).isEmpty
    }
}
