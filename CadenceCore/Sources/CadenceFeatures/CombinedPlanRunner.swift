import Foundation
import Observation
import CadenceCore

/// A device-independent execution contract for the first combined runner.
/// Strength and instruction items are deliberately rejected at construction so
/// an authored plan cannot silently lose work at the start boundary.
public struct CombinedExecutionPlan: Codable, Equatable, Sendable {
    public enum Step: Codable, Equatable, Sendable {
        case cardio(CardioItemSnapshot)
        case mobility(MobilityItemSnapshot)

        public var id: UUID {
            switch self {
            case let .cardio(item): return item.id
            case let .mobility(item): return item.id
            }
        }

        public var title: String {
            switch self {
            case let .cardio(item): return item.title
            case let .mobility(item): return item.title
            }
        }

        public var isCardio: Bool {
            if case .cardio = self { return true }
            return false
        }

        /// A timed cardio prescription can advance without an extra tap. Open
        /// cardio, distance-only cardio, and mobility always require an
        /// explicit completion action.
        public var timedDurationSeconds: Int? {
            switch self {
            case .mobility:
                return nil
            case let .cardio(item):
                if let duration = item.durationSeconds { return max(0, duration) }
                guard let data = item.intervalPlanData,
                      let intervals = try? JSONDecoder().decode(Intervals.self, from: data)
                else { return nil }
                let warmup = intervals.warmupSeconds ?? 0
                let cooldown = intervals.cooldownSeconds ?? 0
                let work = intervals.work.durationSeconds ?? 0
                let recovery = intervals.recovery.durationSeconds ?? 0
                guard intervals.rounds > 0, work + recovery > 0 else { return nil }
                return warmup + (intervals.rounds * (work + recovery)) + cooldown
            }
        }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case unsupportedBoundary(PlanExecutionBoundary)
        case noExecutableItems
    }

    public let sessionID: UUID
    public let title: String
    public let steps: [Step]

    public init(session: Session) throws {
        guard session.executionBoundary.canStartCombinedRunner else {
            throw Error.unsupportedBoundary(session.executionBoundary)
        }
        let snapshots = PlanSessionSnapshot(session: session).items.compactMap { item -> Step? in
            switch item {
            case let .cardio(value): return .cardio(value)
            case let .mobility(value): return .mobility(value)
            case .strength, .instruction: return nil
            }
        }
        guard !snapshots.isEmpty else { throw Error.noExecutableItems }
        self.sessionID = session.id
        self.title = session.title
        self.steps = snapshots
    }

    public var timedDurationSeconds: Int {
        steps.compactMap(\.timedDurationSeconds).reduce(0, +)
    }
}

public enum CombinedRunnerState: String, Codable, Equatable, Sendable {
    case idle
    case running
    case paused
    case finished
    case cancelled
}

/// Headless state machine used by the iPhone combined cardio/mobility surface.
/// It is intentionally clock-driven: tests and the UI provide elapsed seconds,
/// so no timer or simulator is required to prove sequencing and completion.
@Observable
public final class CombinedPlanRunner {
    public let plan: CombinedExecutionPlan
    public private(set) var state: CombinedRunnerState = .idle
    public private(set) var currentStepIndex = 0
    public private(set) var elapsedSeconds = 0
    public private(set) var currentStepElapsedSeconds = 0
    public private(set) var completedStepIDs: [UUID] = []
    public private(set) var startedAt: Date?
    public private(set) var endedAt: Date?

    public init(plan: CombinedExecutionPlan) {
        self.plan = plan
    }

    public var currentStep: CombinedExecutionPlan.Step? {
        guard plan.steps.indices.contains(currentStepIndex) else { return nil }
        return plan.steps[currentStepIndex]
    }

    public var isComplete: Bool { state == .finished || state == .cancelled }

    public func start(now: Date = Date()) {
        guard state == .idle else { return }
        startedAt = now
        state = .running
    }

    public func pause() {
        guard state == .running else { return }
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        state = .running
    }

    /// Advances the active step's clock. A timed cardio step completes exactly
    /// at its prescription; all other steps remain user-advanced.
    public func tick(seconds: Int = 1) {
        guard state == .running, seconds > 0, currentStep != nil else { return }
        elapsedSeconds += seconds
        currentStepElapsedSeconds += seconds
        if let duration = currentStep?.timedDurationSeconds,
           currentStepElapsedSeconds >= duration {
            completeCurrentStep()
        }
    }

    /// Explicitly completes open cardio or mobility, or advances a timed step
    /// early when the athlete chooses to finish the prescription.
    public func completeCurrentStep() {
        guard state == .running, let step = currentStep else { return }
        if !completedStepIDs.contains(step.id) { completedStepIDs.append(step.id) }
        if currentStepIndex + 1 < plan.steps.count {
            currentStepIndex += 1
            currentStepElapsedSeconds = 0
        } else {
            state = .finished
            endedAt = startedAt.map { $0.addingTimeInterval(TimeInterval(elapsedSeconds)) }
        }
    }

    @discardableResult
    public func finish(now: Date = Date()) -> Bool {
        guard state == .running || state == .paused else { return false }
        if let step = currentStep, !completedStepIDs.contains(step.id) {
            completedStepIDs.append(step.id)
        }
        state = .finished
        endedAt = now
        return true
    }

    @discardableResult
    public func cancel(now: Date = Date()) -> Bool {
        guard state != .finished, state != .cancelled else { return false }
        state = .cancelled
        endedAt = now
        return true
    }
}
