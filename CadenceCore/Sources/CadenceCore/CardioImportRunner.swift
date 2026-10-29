import Foundation

/// Outcome of one committed cardio import.
public struct CardioImportReport: Equatable, Sendable {
    public var inserted: Int
    public var removed: Int
    public var changed: Bool
    public init(inserted: Int, removed: Int, changed: Bool = false) {
        self.inserted = inserted
        self.removed = removed
        self.changed = changed
    }
    /// True when stored history changed, so projections must be refreshed.
    public var changedHistory: Bool { inserted > 0 || removed > 0 || changed }
}

/// The only successful import sequence: fetch → persist → commit anchor.
/// Any thrown error or cancellation leaves the old anchor untouched, so the
/// next run re-reads the same delta (idempotent by HealthKit UUID).
public enum CardioImportRunner {
    @MainActor
    public static func run(
        provider: any HealthDataProviding,
        persist: (CardioImportDelta) async throws -> CardioImportReport
    ) async throws -> CardioImportReport {
        let delta = try await provider.fetchImportedCardioDelta()
        try Task.checkCancellation()
        let report = try await persist(delta)
        try Task.checkCancellation()
        provider.commitImportedCardioAnchor(delta.nextAnchor)
        return report
    }
}
