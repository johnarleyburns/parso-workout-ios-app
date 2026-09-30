import Foundation

/// The stable references carried by a set while the app moves from one
/// SwiftData configuration to two. Relationships are preferred when present;
/// ID, DB++ key, and finally the captured display name keep history readable
/// during migration or when a related row has not arrived yet.
public struct CrossStoreReferenceResolver: Sendable {
    public struct ExerciseReference: Equatable, Sendable {
        public let id: UUID?
        public let key: String?
        public let name: String

        public init(id: UUID?, key: String?, name: String) {
            self.id = id
            self.key = key
            self.name = name
        }
    }

    public struct PerformerReference: Equatable, Sendable {
        public let id: UUID?
        public let name: String
        public let isOwner: Bool

        public init(id: UUID?, name: String, isOwner: Bool) {
            self.id = id
            self.name = name
            self.isOwner = isOwner
        }
    }

    public init() {}

    public func exercise(for set: SetEntry,
                         exercises: [Exercise]) -> ExerciseReference {
        if let relationship = set.exercise {
            return ExerciseReference(id: relationship.id,
                                     key: ExerciseKey(raw: relationship.name).raw,
                                     name: relationship.name)
        }
        if let id = set.exerciseID,
           let match = exercises.first(where: { $0.id == id }) {
            return ExerciseReference(id: match.id,
                                     key: ExerciseKey(raw: match.name).raw,
                                     name: match.name)
        }
        if let key = set.exerciseKey,
           let match = exercises.first(where: { ExerciseKey(raw: $0.name).raw == key }) {
            return ExerciseReference(id: match.id, key: key, name: match.name)
        }
        let fallback = set.exerciseNameSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExerciseReference(id: set.exerciseID, key: set.exerciseKey,
                                 name: fallback.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown exercise")
    }

    public func performer(for set: SetEntry,
                          people: [Person]) -> PerformerReference {
        if let relationship = set.performedBy {
            return PerformerReference(id: relationship.isMe ? nil : relationship.id,
                                      name: relationship.isMe ? "Me" : relationship.name,
                                      isOwner: relationship.isMe)
        }
        guard let id = set.performerID else {
            return PerformerReference(id: nil, name: "Me", isOwner: true)
        }
        if let match = people.first(where: { $0.id == id }) {
            return PerformerReference(id: match.isMe ? nil : match.id,
                                      name: match.isMe ? "Me" : match.name,
                                      isOwner: match.isMe)
        }
        return PerformerReference(id: id, name: "Partner", isOwner: false)
    }

    /// Backfills every legacy set without changing existing relationships.
    @discardableResult
    public func refresh(_ sets: [SetEntry]) -> Int {
        var changed = 0
        for set in sets {
            let before = (set.exerciseID, set.exerciseKey, set.exerciseNameSnapshot, set.performerID)
            set.refreshCrossStoreReferences()
            let after = (set.exerciseID, set.exerciseKey, set.exerciseNameSnapshot, set.performerID)
            if before.0 != after.0 || before.1 != after.1 || before.2 != after.2 || before.3 != after.3 {
                changed += 1
            }
        }
        return changed
    }
}
