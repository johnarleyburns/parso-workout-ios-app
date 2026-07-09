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
/// narrow, never an O(catalog) scan per render. Also indexes equipment → exercises
/// so the Browse tab can browse by equipment first.
public struct ExerciseFacetIndex<T: EquipmentClassifiable> {
    /// Exercises training each body part, preserving the input order.
    public let byBodyPart: [BodyPart: [T]]
    /// Equipment types present for each body part, in canonical order.
    public let equipmentByBodyPart: [BodyPart: [Equipment]]
    /// Exercises grouped by equipment type, preserving input order.
    public let byEquipment: [Equipment: [T]]
    /// Body parts that have exercises of each equipment type.
    public let bodyPartsByEquipment: [Equipment: [BodyPart]]

    public init(_ items: [T]) {
        var parts: [BodyPart: [T]] = [:]
        var equip: [Equipment: [T]] = [:]
        for item in items {
            for part in item.bodyParts { parts[part, default: []].append(item) }
            if let eq = item.equipmentValue { equip[eq, default: []].append(item) }
        }
        var equipment: [BodyPart: [Equipment]] = [:]
        for (part, list) in parts {
            equipment[part] = Self.equipmentPresent(in: list)
        }
        var bodyPartsForEq: [Equipment: [BodyPart]] = [:]
        for (eq, list) in equip {
            let bps = BodyPart.allCases.filter { p in list.contains { $0.bodyParts.contains(p) } }
            bodyPartsForEq[eq] = bps
        }
        self.byBodyPart = parts
        self.equipmentByBodyPart = equipment
        self.byEquipment = equip
        self.bodyPartsByEquipment = bodyPartsForEq
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

    /// All exercises of a given equipment type, unfiltered by body part.
    public func exercises(forEquipment eq: Equipment, bodyPart: BodyPart? = nil) -> [T] {
        let base = byEquipment[eq] ?? []
        guard let part = bodyPart else { return base }
        return base.filter { $0.bodyParts.contains(part) }
    }

    /// Body parts that have exercises of the given equipment type.
    public func bodyParts(forEquipment eq: Equipment) -> [BodyPart] {
        bodyPartsByEquipment[eq] ?? []
    }

    /// The distinct equipment types among `items`, in canonical `Equipment.allCases`
    /// order. Untagged (`nil`) equipment is ignored.
    public static func equipmentPresent(in items: [T]) -> [Equipment] {
        let present = Set(items.compactMap { $0.equipmentValue })
        return Equipment.allCases.filter { present.contains($0) }
    }
}

extension Exercise: EquipmentClassifiable {}
