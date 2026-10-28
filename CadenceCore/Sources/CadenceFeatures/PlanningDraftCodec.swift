import Foundation
import CadenceCore

/// Encodes/decodes an `EditablePlan` through the explicit, versioned
/// `PlanningDraftPayload` DTO. Decoding never mutates stored rows.
public enum PlanningDraftCodec {
    public static func encode(_ plan: EditablePlan) throws -> Data {
        try JSONEncoder().encode(PlanningDraftPayload(plan: EditablePlanPayload(plan)))
    }

    public static func decode(_ data: Data, version: Int) throws -> EditablePlan {
        guard version == PlanningDraftPayload.currentVersion else {
            throw PlanningDraftCodecError.unsupportedVersion(version)
        }
        return try JSONDecoder().decode(PlanningDraftPayload.self, from: data).plan.editablePlan
    }

    public static func decode(_ draft: PlanningDraft) throws -> EditablePlan {
        try decode(draft.payloadData, version: draft.payloadVersion)
    }
}

extension EditableSetPayload {
    init(_ set: EditableSet) {
        self.init(id: set.id, targetReps: set.targetReps, targetWeight: set.targetWeight,
                  loadModeRaw: set.loadMode.rawValue, oneRepMaxPercent: set.oneRepMaxPercent)
    }

    var editableSet: EditableSet {
        EditableSet(id: id, targetReps: targetReps, targetWeight: targetWeight,
                    loadMode: EditableLoadMode(rawValue: loadModeRaw) ?? .straight,
                    oneRepMaxPercent: oneRepMaxPercent)
    }
}

extension EditablePlanPayload {
    init(_ plan: EditablePlan) {
        self.init(
            id: plan.id, title: plan.title, warmupMinutes: plan.warmupMinutes,
            cooldownMinutes: plan.cooldownMinutes,
            exercises: plan.exercises.map { ex in
                EditableExercisePayload(
                    id: ex.id, name: ex.name, notes: ex.notes,
                    supersetGroupRaw: ex.supersetGroup?.raw,
                    sets: ex.sets.map(EditableSetPayload.init),
                    performerPlans: ex.performerPlans.map {
                        EditablePerformerPlanPayload(id: $0.id, performerID: $0.performerID,
                                                     name: $0.name,
                                                     sets: $0.sets.map(EditableSetPayload.init))
                    })
            },
            partnerIDs: plan.partnerIDs, enginePlanId: plan.enginePlanId,
            engineRevisionId: plan.engineRevisionId, enginePlanJSON: plan.enginePlanJSON,
            suggestedWorkoutStyleRaw: plan.suggestedWorkoutStyle?.rawValue,
            recommendationRationale: plan.recommendationRationale.map { r in
                RationalePayload(whyWorkout: r.whyWorkout, exercises: r.exercises.map {
                    .init(exerciseName: $0.exerciseName, whyExercise: $0.whyExercise,
                          whySetRep: $0.whySetRep)
                })
            })
    }

    var editablePlan: EditablePlan {
        EditablePlan(
            title: title, warmupMinutes: warmupMinutes, cooldownMinutes: cooldownMinutes,
            exercises: exercises.map { ex in
                EditableExercise(
                    name: ex.name, sets: ex.sets.map(\.editableSet), notes: ex.notes,
                    performerPlans: ex.performerPlans.map {
                        EditablePerformerPlan(id: $0.id, performerID: $0.performerID,
                                              name: $0.name, sets: $0.sets.map(\.editableSet))
                    },
                    supersetGroup: ex.supersetGroupRaw.map(SupersetGroupID.init(raw:)),
                    id: ex.id)
            },
            partnerIDs: partnerIDs, enginePlanId: enginePlanId,
            engineRevisionId: engineRevisionId, enginePlanJSON: enginePlanJSON,
            suggestedWorkoutStyle: suggestedWorkoutStyleRaw.flatMap(SuggestedWorkoutStyle.init(rawValue:)),
            recommendationRationale: recommendationRationale.map { r in
                SuggestedWorkoutRationale(whyWorkout: r.whyWorkout, exercises: r.exercises.map {
                    SuggestedExerciseRationale(exerciseName: $0.exerciseName,
                                               whyExercise: $0.whyExercise, whySetRep: $0.whySetRep)
                })
            },
            id: id)
    }
}
