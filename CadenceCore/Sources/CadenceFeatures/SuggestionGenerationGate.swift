import Foundation

/// Rejects results produced for a suggestion snapshot that has been
/// invalidated by a completion, cancellation, or newer request.
public struct SuggestionGenerationGate: Sendable {
    private(set) public var currentID: UUID

    public init(currentID: UUID = UUID()) {
        self.currentID = currentID
    }

    @discardableResult
    public mutating func begin() -> UUID {
        currentID = UUID()
        return currentID
    }

    public mutating func invalidate() {
        currentID = UUID()
    }

    public func accepts(_ id: UUID) -> Bool {
        currentID == id
    }
}
