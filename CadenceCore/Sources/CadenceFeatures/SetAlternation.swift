import Foundation
import CadenceCore

/// The single answer for "whose turn is it next" on a shared exercise card and
/// in the set editor. The two surfaces used to derive it independently and
/// disagreed (field test 2026-08-20 #1): the pending-row interleave was a
/// column-major round-robin that could emit the same performer twice in a row,
/// and `SessionView.nextPerson()` rotated on the whole session instead of the
/// exercise, so the card and the editor could pick different next people.
public enum SetAlternation {

    /// Evenly-spread interleave of per-performer pending rows. Never emits two
    /// consecutive rows from the same performer while at least two performers
    /// still have outstanding rows (decision D2). Deterministic: given the same
    /// groups it always returns the same sequence.
    ///
    /// Greedy fair queue: repeatedly emit the next row from the group with the
    /// most outstanding rows that is NOT the group of the last emitted row,
    /// choosing caller-order-first among ties; when only one group has rows
    /// left, emit its remainder (unavoidable and correct).
    public static func spread(_ groups: [[SessionRenderModel.PendingSetDisplay]]) -> [SessionRenderModel.PendingSetDisplay] {
        var result: [SessionRenderModel.PendingSetDisplay] = []
        var remaining: [[SessionRenderModel.PendingSetDisplay]] = groups
        var lastGroup: Int?
        while true {
            var candidates = remaining.indices.filter { !remaining[$0].isEmpty && $0 != lastGroup }
            if candidates.isEmpty {
                candidates = remaining.indices.filter { !remaining[$0].isEmpty }
            }
            guard let pick = candidates.max(by: { lhs, rhs in
                if remaining[lhs].count == remaining[rhs].count {
                    return lhs > rhs
                }
                return remaining[lhs].count < remaining[rhs].count
            }) else { break }
            result.append(remaining[pick].removeFirst())
            lastGroup = pick
        }
        return result
    }

    /// Who should enter the next set for an exercise.
    /// - `pendingSets` non-empty → the performer of the first pending row (the
    ///   card's alternation answer).
    /// - `pendingSets` empty (silent/unplanned exercise) → the next member in
    ///   `rosterOrder` after `lastLoggedPerformerID`, defaulting to the owner
    ///   (nil) when there is nothing to rotate from.
    /// The owner is represented by `nil` throughout.
    public static func nextPerformerID(pendingSets: [SessionRenderModel.PendingSetDisplay],
                                       rosterOrder: [UUID?],
                                       lastLoggedPerformerID: UUID?) -> UUID? {
        if let first = pendingSets.first {
            return first.performerID
        }
        guard let lastLoggedPerformerID,
              let lastIndex = rosterOrder.firstIndex(of: lastLoggedPerformerID) else {
            return nil
        }
        return rosterOrder[(lastIndex + 1) % rosterOrder.count]
    }
}
