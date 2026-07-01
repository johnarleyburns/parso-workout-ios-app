import Foundation

/// Resolves who is "in" a strength session for partner attribution.
///
/// Partners are **opt-in**: an empty `activePartnerIDs` means the user is
/// training solo (just the owner), NOT "show everyone". This is the single
/// source of truth for the session view's roster, the WHO column, and the
/// performer pickers, so "select no partners" and "remove the last partner"
/// both correctly collapse to solo (field-testing §04 bug fix).
public enum SessionRoster {

    /// Partners explicitly scoped to a session, in the configured session order.
    /// Empty when the user chose none (solo).
    public static func scopedPartners(activePartnerIDs: [String],
                                      allPeople: [Person]) -> [Person] {
        guard !activePartnerIDs.isEmpty else { return [] }
        let orderedIDs = activePartnerIDs.compactMap(UUID.init(uuidString:))
        let peopleByID = Dictionary(allPeople.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        return orderedIDs.compactMap { id in
            guard seen.insert(id).inserted,
                  let person = peopleByID[id],
                  !person.isMe else { return nil }
            return person
        }
    }

    /// The configured session roster. Solo sessions resolve to just the owner.
    ///
    /// Back-compat: older sessions stored partner ids only, so the owner remains
    /// first until a UI reorder writes the owner's id as an explicit roster member.
    public static func roster(activePartnerIDs: [String],
                              allPeople: [Person]) -> [Person] {
        let owners = allPeople.filter(\.isMe)
        guard !activePartnerIDs.isEmpty else { return owners }

        let orderedIDs = activePartnerIDs.compactMap(UUID.init(uuidString:))
        let peopleByID = Dictionary(allPeople.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        let ordered = orderedIDs.compactMap { id -> Person? in
            guard seen.insert(id).inserted else { return nil }
            return peopleByID[id]
        }

        if ordered.contains(where: \.isMe) {
            return ordered
        }

        return owners + ordered.filter { !$0.isMe }
    }

    /// At least one partner is scoped to the session.
    public static func hasPartners(activePartnerIDs: [String],
                                   allPeople: [Person]) -> Bool {
        !scopedPartners(activePartnerIDs: activePartnerIDs, allPeople: allPeople).isEmpty
    }

    /// Partners that may be picked when attributing a set: the scoped partners
    /// PLUS anyone already attributed to a set in the session (so a set
    /// mistakenly attributed to a now-unscoped partner can still be corrected
    /// back to "Me"). Session-scoped partners keep configured order; attributed
    /// extras are appended by name. Owner excluded (the caller adds "Me").
    public static func attributablePartners(activePartnerIDs: [String],
                                            allPeople: [Person],
                                            includingAttributed attributedIDs: [UUID] = []) -> [Person] {
        let scoped = scopedPartners(activePartnerIDs: activePartnerIDs, allPeople: allPeople)
        let scopedIDs = Set(scoped.map(\.id))
        let extras = allPeople
            .filter { !$0.isMe && attributedIDs.contains($0.id) && !scopedIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return scoped + extras
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
