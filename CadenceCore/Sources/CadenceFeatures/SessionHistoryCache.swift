import Foundation
import Observation
import CadenceCore

/// Memo wrapper for `SessionRenderModel.build`. On `refresh(signature:build:)`,
/// if the signature matches the last one, the rebuild is skipped. `rebuildCount`
/// is incremented only when the signature changes — a testable performance proof.
@Observable
public final class SessionHistoryCache {
    public var state = SessionRenderModel.State(contexts: [], prSetIDs: [])
    public private(set) var rebuildCount = 0
    private var lastSignature: SessionRenderModel.Signature?

    public init() {}

    /// Recomputes `state` only when `signature` differs from the prior call.
    /// `build` is a closure so the caller can capture a `ModelContext` without
    /// storing it on the cache.
    public func refresh(signature: SessionRenderModel.Signature,
                        build: () -> SessionRenderModel.State) {
        if let last = lastSignature, last == signature { return }
        rebuildCount += 1
        lastSignature = signature
        state = build()
    }
}
