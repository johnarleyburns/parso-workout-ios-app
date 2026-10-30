import Foundation
import CadenceCore

/// What caused an automatic or manual HealthKit cardio import request.
public enum CardioImportTrigger: String, Equatable, Sendable {
    case authorization, foreground, observer, homeDisplay, manualRefresh, retry
}

/// Observable result of the single serialized import pipeline.
public enum CardioImportState: Equatable, Sendable {
    case idle
    case syncing
    /// Committed import; `report.changedHistory == false` is a genuine empty read.
    case completed(Date, CardioImportReport)
    case failed(String)
    /// HealthKit is not available on this device. Distinct from an empty read.
    case unavailable
}

/// Single serial owner of the #416 fetch → persist → commit-anchor sequence.
/// Every trigger calls `request`; a trigger arriving mid-run joins the running
/// operation and schedules exactly one follow-up pass, so two anchor commits
/// can never run in parallel and no trigger owns its own cursor.
@MainActor
public final class CardioImportCoordinator {
    public typealias Persist = (CardioImportDelta) async throws -> CardioImportReport

    private let provider: any HealthDataProviding
    private let persist: Persist
    private let now: () -> Date
    private let onState: (CardioImportState) -> Void
    /// Called once per committed report that changed stored history. Consumers
    /// (history/coach refresh, Watch publish) run only after persistence succeeded.
    private let onCommittedChange: (CardioImportReport) -> Void

    private var running: Task<CardioImportState, Never>?
    private var followUpPending = false
    public private(set) var state: CardioImportState = .idle
    /// Committed passes, for tests and diagnostics.
    public private(set) var passCount = 0

    public init(provider: any HealthDataProviding,
                persist: @escaping Persist,
                now: @escaping () -> Date = Date.init,
                onState: @escaping (CardioImportState) -> Void = { _ in },
                onCommittedChange: @escaping (CardioImportReport) -> Void = { _ in }) {
        self.provider = provider
        self.persist = persist
        self.now = now
        self.onState = onState
        self.onCommittedChange = onCommittedChange
    }

    public var isRunning: Bool { running != nil }

    /// Runs (or joins) the import and returns the final state once all pending
    /// follow-up passes have finished.
    @discardableResult
    public func request(_ trigger: CardioImportTrigger) async -> CardioImportState {
        if let running {
            followUpPending = true
            return await running.value
        }
        let task = Task { @MainActor in await self.drain() }
        running = task
        return await task.value
    }

    private func drain() async -> CardioImportState {
        var result = CardioImportState.idle
        repeat {
            followUpPending = false
            result = await runOnce()
        } while followUpPending
        running = nil
        return result
    }

    private func runOnce() async -> CardioImportState {
        guard provider.isHealthDataAvailable else {
            return publish(.unavailable)
        }
        _ = publish(.syncing)
        do {
            let report = try await CardioImportRunner.run(provider: provider, persist: persist)
            passCount += 1
            let done = publish(.completed(now(), report))
            if report.changedHistory { onCommittedChange(report) }
            return done
        } catch is CancellationError {
            return publish(.idle)
        } catch {
            return publish(.failed(error.localizedDescription))
        }
    }

    private func publish(_ new: CardioImportState) -> CardioImportState {
        state = new
        onState(new)
        return new
    }

    /// Runs an observer delivery and guarantees HealthKit's completion handler
    /// fires exactly once on success, failure, cancellation and no-op paths.
    public func handleObserverDelivery(_ completion: HealthObserverCompletion) async {
        defer { completion.finish() }
        await request(.observer)
    }
}
