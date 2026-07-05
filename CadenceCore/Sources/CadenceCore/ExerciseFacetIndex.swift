import Foundation

/// Anything the exercise picker's equipment sub-filter can classify: its coarse
/// body parts (already derived from muscle ids) and its equipment type. Both the
/// SwiftData `Exercise` and lightweight test doubles conform.
public protocol EquipmentClassifiable {
    var bodyParts: Set<BodyPart> { get }
    var equipmentValue: Equipment? { get }
}

/// A precomputed body-part → exercises / body-part → equipment index (built once
/// from the loaded catalog) so the picker's **equipment sub-filter** — a second
/// chip row under the body-part row — is an O(1) dictionary lookup plus an O(m)
/// narrow, never an O(catalog) scan per render. Mirrors `ExerciseSearchIndex`:
/// build once when the catalog size changes, reuse across taps (keeps selecting a
/// body part + equipment instant even over the full 800+ movement library).
public struct ExerciseFacetIndex<T: EquipmentClassifiable> {
    /// Exercises training each body part, preserving the input order (the picker
    /// feeds a name-sorted catalog, so rows stay alphabetical).
    public let byBodyPart: [BodyPart: [T]]
    /// Equipment types present for each body part, in canonical `Equipment.allCases`
    /// order — the order the sub-filter chips render in.
    public let equipmentByBodyPart: [BodyPart: [Equipment]]

    public init(_ items: [T]) {
        var parts: [BodyPart: [T]] = [:]
        for item in items {
            for part in item.bodyParts { parts[part, default: []].append(item) }
        }
        var equipment: [BodyPart: [Equipment]] = [:]
        for (part, list) in parts {
            equipment[part] = Self.equipmentPresent(in: list)
        }
        self.byBodyPart = parts
        self.equipmentByBodyPart = equipment
    }

    /// Exercises training `part`, optionally narrowed to a single equipment type.
    public func exercises(for part: BodyPart, equipment: Equipment? = nil) -> [T] {
        let base = byBodyPart[part] ?? []
        guard let equipment else { return base }
        return base.filter { $0.equipmentValue == equipment }
    }

    /// Equipment types available for `part` (deduped, canonical order). Empty when
    /// the part is unknown or has no equipment-tagged movements.
    public func equipment(for part: BodyPart) -> [Equipment] {
        equipmentByBodyPart[part] ?? []
    }

    /// The distinct equipment types among `items`, in canonical `Equipment.allCases`
    /// order. Untagged (`nil`) equipment is ignored.
    public static func equipmentPresent(in items: [T]) -> [Equipment] {
        let present = Set(items.compactMap { $0.equipmentValue })
        return Equipment.allCases.filter { present.contains($0) }
    }
}

extension Exercise: EquipmentClassifiable {}
