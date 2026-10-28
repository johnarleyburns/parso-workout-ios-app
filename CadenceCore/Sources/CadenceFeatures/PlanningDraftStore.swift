import Foundation
import SwiftData
import CadenceCore

/// The single mutation boundary for the unscheduled Planning Draft. Views and
/// coordinators never encode payloads or write `PlanningDraft` rows directly.
///
/// Lives in `CadenceFeatures` (not `CadenceCore`) because `EditablePlan` and
/// `PlanningDraftCodec` are defined here and `CadenceCore` cannot depend on it.
@MainActor
public protocol PlanningDraftManaging {
    func currentDraft(in context: ModelContext) throws -> PlanningDraft?
    func createIfNeeded(in context: ModelContext) throws -> PlanningDraft
    func add(_ exercise: Exercise, to draftID: UUID?, in context: ModelContext) throws -> PlanningDraft
    func replacePlan(_ plan: EditablePlan, in draft: PlanningDraft, context: ModelContext) throws
    func discard(_ draft: PlanningDraft, in context: ModelContext) throws
}

@MainActor
public struct PlanningDraftStore: PlanningDraftManaging {
    /// Owner history for a movement name; the app supplies the real lookup so
    /// seeding matches `WorkoutPlanEditor+Editing.swift`.
    public typealias HistoryProvider = @MainActor (_ exerciseName: String, _ context: ModelContext)
        -> PartnerPlanResolver.ExerciseHistory

    private let originDevice: String
    private let historyProvider: HistoryProvider
    private let encode: (EditablePlan) throws -> Data
    private let save: (ModelContext) throws -> Void
    private let now: () -> Date

    public init(originDevice: String = "",
                historyProvider: @escaping HistoryProvider = { _, _ in .empty },
                encode: @escaping (EditablePlan) throws -> Data = PlanningDraftCodec.encode,
                save: @escaping (ModelContext) throws -> Void = { try $0.save() },
                now: @escaping () -> Date = { Date() }) {
        self.originDevice = originDevice
        self.historyProvider = historyProvider
        self.encode = encode
        self.save = save
        self.now = now
    }

    // MARK: Reads

    /// Newest visible draft; ties on `updatedAt` break by `createdAt`, then id.
    public func currentDraft(in context: ModelContext) throws -> PlanningDraft? {
        try visibleDrafts(in: context).first
    }

    public func plan(for draft: PlanningDraft) throws -> EditablePlan {
        try PlanningDraftCodec.decode(draft)
    }

    public func exerciseCount(for draft: PlanningDraft) throws -> Int {
        try plan(for: draft).exercises.count
    }

    /// Case-insensitive, matching the duplicate rule in `add`.
    public func contains(exerciseNamed name: String, in draft: PlanningDraft) throws -> Bool {
        try plan(for: draft).exercises.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func exerciseNames(for draft: PlanningDraft) throws -> [String] {
        try plan(for: draft).exercises.map(\.name)
    }

    // MARK: Mutations

    public func createIfNeeded(in context: ModelContext) throws -> PlanningDraft {
        let visible = try visibleDrafts(in: context)
        if let keeper = visible.first {
            try reconcile(keeper: keeper, duplicates: Array(visible.dropFirst()), in: context)
            return keeper
        }
        let plan = EditablePlan(warmupMinutes: 0, cooldownMinutes: 0, exercises: [])
        let draft = PlanningDraft(title: Self.title(for: plan), payloadData: try encode(plan),
                                  createdAt: now(), updatedAt: now(), originDevice: originDevice)
        context.insert(draft)
        do { try save(context) } catch {
            context.delete(draft)
            throw error
        }
        return draft
    }

    public func add(_ exercise: Exercise, to draftID: UUID?, in context: ModelContext) throws -> PlanningDraft {
        let draft = try resolve(draftID, in: context)
        var plan = try PlanningDraftCodec.decode(draft)
        guard !plan.exercises.contains(where: {
            $0.name.caseInsensitiveCompare(exercise.name) == .orderedSame
        }) else { return draft }
        let seeded = PartnerPlanResolver.ownerSeedSets(
            history: historyProvider(exercise.name, context), defaultReps: 10)
        plan.exercises.append(EditableExercise(name: exercise.name, sets: seeded, notes: ""))
        try replacePlan(plan, in: draft, context: context)
        return draft
    }

    public func removeExercise(id: UUID, from draft: PlanningDraft, context: ModelContext) throws {
        var plan = try PlanningDraftCodec.decode(draft)
        plan.exercises.removeAll { $0.id == id }
        try replacePlan(plan, in: draft, context: context)
    }

    public func moveExercises(from source: IndexSet, to destination: Int,
                              in draft: PlanningDraft, context: ModelContext) throws {
        var plan = try PlanningDraftCodec.decode(draft)
        let moving = source.sorted().compactMap { plan.exercises.indices.contains($0) ? plan.exercises[$0] : nil }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) where plan.exercises.indices.contains(index) {
            plan.exercises.remove(at: index)
        }
        let target = min(max(destination - before, 0), plan.exercises.count)
        plan.exercises.insert(contentsOf: moving, at: target)
        try replacePlan(plan, in: draft, context: context)
    }

    /// Encode first, then apply and save once. Any failure restores the prior
    /// persisted fields so a valid payload is never partially overwritten.
    public func replacePlan(_ plan: EditablePlan, in draft: PlanningDraft, context: ModelContext) throws {
        let data = try encode(plan)
        let previous = (draft.title, draft.payloadData, draft.payloadVersion, draft.updatedAt)
        draft.title = Self.title(for: plan)
        draft.payloadData = data
        draft.payloadVersion = PlanningDraftPayload.currentVersion
        draft.updatedAt = now()
        do { try save(context) } catch {
            (draft.title, draft.payloadData, draft.payloadVersion, draft.updatedAt) = previous
            throw error
        }
    }

    /// Soft delete; a later `createIfNeeded` starts a fresh draft.
    public func discard(_ draft: PlanningDraft, in context: ModelContext) throws {
        let previous = (draft.deletedAt, draft.updatedAt)
        let stamp = now()
        draft.deletedAt = stamp
        draft.updatedAt = stamp
        do { try save(context) } catch {
            (draft.deletedAt, draft.updatedAt) = previous
            throw error
        }
    }

    // MARK: Helpers

    private func visibleDrafts(in context: ModelContext) throws -> [PlanningDraft] {
        try context.fetch(FetchDescriptor<PlanningDraft>(predicate: #Predicate { $0.deletedAt == nil }))
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    /// The requested draft if it is visible, otherwise the current one
    /// (created when absent). Legacy duplicates are soft-deleted.
    private func resolve(_ id: UUID?, in context: ModelContext) throws -> PlanningDraft {
        let visible = try visibleDrafts(in: context)
        guard let first = visible.first else { return try createIfNeeded(in: context) }
        let keeper = id.flatMap { id in visible.first { $0.id == id } } ?? first
        try reconcile(keeper: keeper, duplicates: visible.filter { $0 !== keeper }, in: context)
        return keeper
    }

    private func reconcile(keeper: PlanningDraft, duplicates: [PlanningDraft],
                           in context: ModelContext) throws {
        guard !duplicates.isEmpty else { return }
        let stamp = now()
        let previous = duplicates.map(\.deletedAt)
        duplicates.forEach { $0.deletedAt = stamp }
        do { try save(context) } catch {
            for (draft, old) in zip(duplicates, previous) { draft.deletedAt = old }
            throw error
        }
    }

    private static func title(for plan: EditablePlan) -> String {
        let trimmed = plan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Workout" : trimmed
    }
}
