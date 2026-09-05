import Foundation
import SwiftData
import CadenceCore

public enum WatchStrengthSyncApplier {
    public enum AppliedAction: Equatable, Sendable {
        case logSet
        case endSession
        case discardSession
        case deleteExercise
        case deleteSet
        case ignored
    }

    @discardableResult
    public static func apply(userInfo: [String: Any],
                             in context: ModelContext,
                             phoneActiveID: UUID? = nil) throws -> AppliedAction {
        guard let action = userInfo["action"] as? String else { return .ignored }
        switch action {
        case "log_set":
            return try applyLogSet(userInfo, in: context)
        case "end_session":
            return try applyEndSession(userInfo, in: context, phoneActiveID: phoneActiveID)
        case "discard_session":
            return try applyDiscardSession(userInfo, in: context)
        case "delete_exercise":
            return try applyDeleteExercise(userInfo, in: context)
        case "delete_set":
            return try applyDeleteSet(userInfo, in: context)
        default:
            return .ignored
        }
    }

    private static func applyLogSet(_ info: [String: Any],
                                    in context: ModelContext) throws -> AppliedAction {
        guard let sessionID = uuid(info["session_id"]),
              let exerciseName = info["exercise"] as? String,
              let weight = info["weight"] as? Double,
              let reps = info["reps"] as? Int else { return .ignored }

        if let setID = uuid(info["set_id"]),
           !(try fetchSet(id: setID, in: context)).isEmpty {
            return .ignored
        }

        let completedAt = date(info["timestamp"]) ?? Date()
        let planPayload = watchPlanPayload(from: info)
        let session = try ensureSession(
            id: sessionID,
            title: info["session_title"] as? String,
            date: completedAt,
            plannedExerciseNames: info["planned_exercises"] as? [String],
            plannedRepLadder: info["planned_rep_ladder"] as? [Int],
            planKey: info["plan_key"] as? String,
            planPayload: planPayload,
            in: context
        )

        let exercise = try WorkoutRepository.findOrCreateExercise(named: exerciseName, in: context)
        let performer = try resolvedPerformer(info, in: context)
        let set = try WorkoutRepository.addSet(
            to: session,
            exercise: exercise,
            weightKg: weight,
            reps: reps,
            rpe: info["rpe"] as? Double,
            isWarmup: info["is_warmup"] as? Bool ?? false,
            performedBy: performer,
            in: context
        )
        if let setID = uuid(info["set_id"]) {
            set.id = setID
            try context.save()
        }
        return .logSet
    }

    private static func applyEndSession(_ info: [String: Any],
                                        in context: ModelContext,
                                        phoneActiveID: UUID?) throws -> AppliedAction {
        guard let sessionID = uuid(info["session_id"]) else { return .ignored }
        guard WatchSessionEndPolicy.shouldApplyEnd(sessionID: sessionID, phoneActiveID: phoneActiveID) else {
            return .ignored
        }

        let endedAt = date(info["ended_at"]) ?? Date()
        let planPayload = watchPlanPayload(from: info)
        let session = try ensureSession(
            id: sessionID,
            title: info["session_title"] as? String,
            date: endedAt,
            plannedExerciseNames: (info["planned_exercises"] as? [String]) ?? (info["exercises"] as? [String]),
            plannedRepLadder: info["planned_rep_ladder"] as? [Int],
            planKey: info["plan_key"] as? String,
            planPayload: planPayload,
            in: context
        )
        session.endedAt = endedAt
        if let cooldown = info["cooldown_seconds"] as? Int {
            session.cooldownSeconds = Double(cooldown)
        }
        session.updatedAt = Date()
        try context.save()
        return .endSession
    }

    private static func applyDiscardSession(_ info: [String: Any],
                                            in context: ModelContext) throws -> AppliedAction {
        guard let sessionID = uuid(info["session_id"]) else { return .ignored }
        for session in try fetchSessions(id: sessionID, in: context) {
            context.delete(session)
        }
        try context.save()
        return .discardSession
    }

    private static func applyDeleteExercise(_ info: [String: Any],
                                            in context: ModelContext) throws -> AppliedAction {
        guard let sessionID = uuid(info["session_id"]),
              let name = info["exercise"] as? String,
              let session = try fetchSessions(id: sessionID, in: context).first else { return .ignored }

        if let exercise = session.exercisesInOrder.first(where: {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            try WorkoutRepository.removeExercise(exercise, from: session, in: context)
        } else {
            try WorkoutRepository.removePlannedExercise(named: name, from: session, in: context)
        }
        return .deleteExercise
    }

    private static func applyDeleteSet(_ info: [String: Any],
                                       in context: ModelContext) throws -> AppliedAction {
        guard let setID = uuid(info["set_id"]),
              let set = try fetchSet(id: setID, in: context).first else { return .ignored }
        try WorkoutRepository.deleteSet(set, in: context)
        return .deleteSet
    }

    private static func ensureSession(id: UUID,
                                      title: String?,
                                      date: Date,
                                      plannedExerciseNames: [String]?,
                                      plannedRepLadder: [Int]?,
                                      planKey: String?,
                                      planPayload: WatchPlanPayload?,
                                      in context: ModelContext) throws -> WorkoutSession {
        if let existing = try fetchSessions(id: id, in: context).first {
            applySessionMetadata(existing,
                                 title: title,
                                 plannedExerciseNames: plannedExerciseNames,
                                 plannedRepLadder: plannedRepLadder,
                                 planKey: planKey,
                                 planPayload: planPayload,
                                 in: context)
            try context.save()
            return existing
        }

        let cleanedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = try WorkoutRepository.createSession(
            title: cleanedTitle?.isEmpty == false ? cleanedTitle! : "Strength",
            date: date,
            in: context
        )
        session.id = id
        session.originDevice = "watch"
        applySessionMetadata(session,
                             title: title,
                             plannedExerciseNames: plannedExerciseNames,
                             plannedRepLadder: plannedRepLadder,
                             planKey: planKey,
                             planPayload: planPayload,
                             in: context)
        try context.save()
        return session
    }

    private static func applySessionMetadata(_ session: WorkoutSession,
                                             title: String?,
                                             plannedExerciseNames: [String]?,
                                             plannedRepLadder: [Int]?,
                                             planKey: String?,
                                             planPayload: WatchPlanPayload?,
                                             in context: ModelContext) {
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { session.title = trimmed }
        }
        if let plannedExerciseNames {
            var resolved: [String] = []
            var seen = Set<String>()
            for name in plannedExerciseNames {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let exercise = try? WorkoutRepository.findOrCreateExercise(named: trimmed, in: context)
                let canonical = exercise?.name ?? trimmed
                guard seen.insert(ExerciseLibrary.lookupKey(canonical)).inserted else { continue }
                resolved.append(canonical)
            }
            if !resolved.isEmpty || session.plannedExerciseNames.isEmpty {
                session.plannedExerciseNames = resolved
            }
        }
        if let plannedRepLadder {
            session.plannedRepLadder = plannedRepLadder.filter { $0 > 0 }
        }
        if let planKey { session.planKey = planKey }
        if let planPayload {
            session.planSessionID = planPayload.planSessionID
            if let strength = planPayload.strength {
                if !strength.exerciseNames.isEmpty {
                    session.plannedExerciseNames = strength.exerciseNames
                }
                if !strength.repLadder.isEmpty {
                    session.plannedRepLadder = strength.repLadder
                }
                if !strength.prescriptions.isEmpty {
                    session.plannedPrescriptions = strength.prescriptions
                }
            }
        }
        session.updatedAt = Date()
    }

    private static func watchPlanPayload(from info: [String: Any]) -> WatchPlanPayload? {
        guard let raw = info[WatchPlanPayload.transportKey] as? [String: Any] else { return nil }
        return WatchPlanPayload(propertyList: raw)
    }

    private static func resolvedPerformer(_ info: [String: Any],
                                          in context: ModelContext) throws -> Person? {
        if let personID = uuid(info["performed_by_id"]),
           let existing = try context.fetch(FetchDescriptor<Person>(
            predicate: #Predicate { $0.id == personID }
           )).first {
            return existing
        }
        if let name = info["performed_by"] as? String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return try WorkoutRepository.findOrCreatePerson(named: trimmed, in: context)
            }
        }
        return nil
    }

    private static func fetchSessions(id: UUID, in context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == id }
        ))
    }

    private static func fetchSet(id: UUID, in context: ModelContext) throws -> [SetEntry] {
        try context.fetch(FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.id == id }
        ))
    }

    private static func uuid(_ value: Any?) -> UUID? {
        if let uuid = value as? UUID { return uuid }
        if let string = value as? String { return UUID(uuidString: string) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        if let seconds = value as? Int { return Date(timeIntervalSince1970: TimeInterval(seconds)) }
        return nil
    }
}
