import Foundation
import SwiftData
import CadenceCore

public enum PlanningDraftPromotionError: Error, Equatable, Sendable {
    case draftNotFound
}

/// Atomic promotion of a Planning Draft. The operation ID becomes the id of the
/// created `ScheduledWorkout` / `WorkoutSession`, so a repeated call (double
/// tap, retry after interruption) returns the original row instead of making a
/// second one. Every failure restores the draft and removes unsaved inserts.
extension PlanningDraftStore {
    @discardableResult
    public func schedule(draftID: UUID, for date: Date, operationID: UUID,
                         calendar: Calendar = .current, originDevice: String = "iphone",
                         in context: ModelContext) throws -> ScheduledWorkout {
        if let existing = try context.fetch(FetchDescriptor<ScheduledWorkout>(
            predicate: #Predicate { $0.id == operationID })).first { return existing }
        let draft = try requireVisibleDraft(draftID, in: context)
        let plan = try PlanningDraftCodec.decode(draft)
        let scheduled = try ScheduledWorkoutStore.make(plan: plan, for: date, promotionID: operationID,
                                                       calendar: calendar, originDevice: originDevice)
        context.insert(scheduled)
        let previous = (draft.deletedAt, draft.updatedAt)
        let stamp = now()
        draft.deletedAt = stamp
        draft.updatedAt = stamp
        do { try save(context) } catch {
            context.delete(scheduled)
            (draft.deletedAt, draft.updatedAt) = previous
            throw error
        }
        return scheduled
    }

    @discardableResult
    public func start(draftID: UUID, operationID: UUID,
                      in context: ModelContext) throws -> WorkoutSession {
        if let existing = try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == operationID })).first {
            // Interrupted after the session saved: finish retiring the draft.
            if let draft = try? requireVisibleDraft(draftID, in: context) { try retire(draft, in: context) }
            return existing
        }
        let draft = try requireVisibleDraft(draftID, in: context)
        let plan = try PlanningDraftCodec.decode(draft)
        for exercise in plan.exercises {
            _ = try WorkoutRepository.findOrCreateExercise(named: exercise.name, in: context)
        }
        let session = WorkoutSession(id: operationID, title: plan.title.isEmpty ? "Workout" : plan.title,
                                     date: now())
        session.activePartnerIDs = plan.partnerIDs.map(\.uuidString)
        plan.apply(to: session)
        context.insert(session)
        do { try retire(draft, in: context) } catch {
            context.delete(session)
            throw error
        }
        return session
    }

    public func discard(draftID: UUID, in context: ModelContext) throws {
        try discard(try requireVisibleDraft(draftID, in: context), in: context)
    }

    private func retire(_ draft: PlanningDraft, in context: ModelContext) throws {
        let previous = (draft.deletedAt, draft.updatedAt)
        let stamp = now()
        draft.deletedAt = stamp
        draft.updatedAt = stamp
        do { try save(context) } catch {
            (draft.deletedAt, draft.updatedAt) = previous
            throw error
        }
    }

    private func requireVisibleDraft(_ id: UUID, in context: ModelContext) throws -> PlanningDraft {
        guard let draft = try context.fetch(FetchDescriptor<PlanningDraft>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil })).first
        else { throw PlanningDraftPromotionError.draftNotFound }
        return draft
    }
}
