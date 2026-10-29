import Foundation
import SwiftData
import Observation
import CadenceCore

/// View-model behind the Workout Draft screen. Every edit goes through
/// `commit`, which persists via `PlanningDraftManaging` before publishing the
/// new plan, so the screen can never drift from the stored draft.
@MainActor
@Observable
public final class PlanningDraftEditorModel {
    public private(set) var plan: EditablePlan
    /// Plain-language description of the last failed save; nil when saved.
    public private(set) var saveError: String?
    public private(set) var isDiscarded = false
    /// Title text the user is typing; persisted after a short debounce.
    public private(set) var pendingTitle: String?

    public let draft: PlanningDraft
    @ObservationIgnored private let drafts: PlanningDraftManaging
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var failedTransform: ((inout EditablePlan) -> Void)?
    @ObservationIgnored private var titleTask: Task<Void, Never>?
    @ObservationIgnored private let debounce: Duration

    public init(drafts: PlanningDraftManaging, context: ModelContext,
                debounce: Duration = .milliseconds(600)) throws {
        let draft = try drafts.createIfNeeded(in: context)
        self.drafts = drafts
        self.context = context
        self.draft = draft
        self.debounce = debounce
        self.plan = try PlanningDraftCodec.decode(draft)
    }

    // MARK: Derived state

    public static let statusText = "Unscheduled · saved automatically"
    public static let emptyMessage = "No exercises yet. Tap Find exercises to add some."

    public var isEmpty: Bool { plan.exercises.isEmpty }
    public var canStartOrSchedule: Bool { !isEmpty && !isDiscarded }
    public var needsDiscardConfirmation: Bool { !isEmpty }
    public var exerciseCountText: String { PlanningDraftSummary.countText(plan.exercises.count) }
    public var displayTitle: String { pendingTitle ?? plan.title }

    // MARK: Persistence

    public func commit(_ transform: @escaping (inout EditablePlan) -> Void) {
        var next = plan
        transform(&next)
        do {
            try drafts.replacePlan(next, in: draft, context: context)
            plan = next
            saveError = nil
            failedTransform = nil
        } catch {
            failedTransform = transform
            saveError = error.localizedDescription
        }
    }

    /// Re-applies the edit that failed to save.
    public func retrySave() {
        if let failedTransform { commit(failedTransform) }
    }

    // MARK: Edits

    /// High-frequency: debounced. `flush()` persists immediately.
    public func editTitle(_ text: String) {
        pendingTitle = text
        titleTask?.cancel()
        let delay = debounce
        titleTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Persists any debounced text edit; call on disappear and backgrounding.
    public func flush() {
        titleTask?.cancel()
        titleTask = nil
        guard let text = pendingTitle else { return }
        pendingTitle = nil
        commit { $0.title = text }
    }

    public func removeExercise(id: UUID) {
        commit { $0.exercises.removeAll { $0.id == id } }
    }

    public func moveExercise(id: UUID, by offset: Int) {
        commit { plan in
            guard let from = plan.exercises.firstIndex(where: { $0.id == id }) else { return }
            let to = from + offset
            guard plan.exercises.indices.contains(to) else { return }
            plan.exercises.insert(plan.exercises.remove(at: from), at: to)
        }
    }

    public func canMove(id: UUID, by offset: Int) -> Bool {
        guard let from = plan.exercises.firstIndex(where: { $0.id == id }) else { return false }
        return plan.exercises.indices.contains(from + offset)
    }

    public func addSet(to exerciseID: UUID) {
        updateExercise(exerciseID) { exercise in
            let last = exercise.sets.last
            exercise.sets.append(EditableSet(targetReps: last?.targetReps ?? 10,
                                             targetWeight: last?.targetWeight,
                                             loadMode: last?.loadMode ?? .straight,
                                             oneRepMaxPercent: last?.oneRepMaxPercent))
            exercise = PartnerPlanResolver.aligned(exercise)
        }
    }

    public func removeSet(exerciseID: UUID, setID: UUID) {
        updateExercise(exerciseID) { exercise in
            guard exercise.sets.count > 1 else { return }
            exercise.sets.removeAll { $0.id == setID }
            exercise = PartnerPlanResolver.aligned(exercise)
        }
    }

    public func setReps(exerciseID: UUID, setID: UUID, reps: Int) {
        updateSet(exerciseID, setID) { $0.targetReps = max(1, min(reps, 999)) }
    }

    public func setWeight(exerciseID: UUID, setID: UUID, weight: Double?) {
        updateSet(exerciseID, setID) { $0.targetWeight = weight.map { max(0, $0) } }
    }

    /// Replaces the roster and re-resolves each exercise's performer plans.
    public func setPartners(_ ids: [UUID], roster: [PartnerPlanResolver.RosterMember],
                            history: @escaping (String, UUID?) -> PartnerPlanResolver.ExerciseHistory) {
        commit { plan in
            plan.partnerIDs = ids
            plan = PartnerPlanResolver.fill(plan: plan, roster: roster, history: history)
        }
    }

    // MARK: Discard

    @discardableResult
    public func discard() -> Bool {
        titleTask?.cancel()
        pendingTitle = nil
        do {
            try drafts.discard(draft, in: context)
            isDiscarded = true
            saveError = nil
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    // MARK: Helpers

    private func updateExercise(_ id: UUID, _ change: @escaping (inout EditableExercise) -> Void) {
        commit { plan in
            guard let index = plan.exercises.firstIndex(where: { $0.id == id }) else { return }
            change(&plan.exercises[index])
        }
    }

    private func updateSet(_ exerciseID: UUID, _ setID: UUID, _ change: @escaping (inout EditableSet) -> Void) {
        updateExercise(exerciseID) { exercise in
            if let index = exercise.sets.firstIndex(where: { $0.id == setID }) {
                change(&exercise.sets[index])
            }
        }
    }
}
