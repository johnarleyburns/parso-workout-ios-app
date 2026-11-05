import Foundation
import SwiftData
import FreeExerciseDBPlusPlus
import FreeExerciseDBPlusPlusFIT

/// Local-only Garmin FIT import/export for completed strength workouts.
///
/// `GarminFITAdapter` (DB++ v1.18.2) is the sole binary codec; nothing here
/// encodes or decodes FIT bytes. This type owns the one explicit mapping
/// between Cladiron persistence (`WorkoutSession`) and canonical DB++ ACTUAL
/// JSON, plus validation, size limits and the atomic persistence step.
///
/// Compatibility contract: a FIT file written by Cladiron carries the full
/// ACTUAL document in a developer-field sidecar and imports losslessly. A FIT
/// file without that sidecar (a native Garmin recording) is never guessed into
/// a strength workout — strict import reports `.sidecarRequired`.
public enum GarminFITBridge {
    /// Hard ceiling applied before any decoding of untrusted input.
    public static let maxFileBytes = 5_000_000
    /// Ceiling for the canonical JSON recovered from the sidecar.
    public static let maxCanonicalBytes = 2_000_000

    // MARK: Errors

    public enum Failure: Error, Equatable, Sendable {
        /// Local workout is missing something the user can fix.
        case invalidWorkout(Reason)
        /// The codec failed to serialize a valid workout.
        case serialization
        /// Input is not a FIT file at all.
        case notFIT
        /// Input is FIT-shaped but truncated/corrupt.
        case malformed
        case tooLarge
        /// Valid FIT with no DB++ sidecar; strict mode cannot reconstruct it.
        case sidecarRequired
        /// Sidecar present but not a valid Cladiron ACTUAL.
        case invalidSidecar
        case cancelled
        case writeFailed
    }

    public enum Reason: String, Equatable, Sendable {
        case notFinished, deleted, noCompletedSets
    }

    // MARK: Export

    public struct ExportedFile: Equatable, Sendable {
        public let filename: String
        public let data: Data
    }

    public static func exportBlockers(for session: WorkoutSession) -> Reason? {
        if session.deletedAt != nil { return .deleted }
        if session.endedAt == nil && !session.isLogged { return .notFinished }
        let completed = session.orderedSets.contains {
            $0.isOwnerSet && !$0.isWarmup && $0.reps > 0 && $0.exercise != nil
        }
        return completed ? nil : .noCompletedSets
    }

    public static func filename(for session: WorkoutSession) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let short = session.id.uuidString.prefix(8).lowercased()
        return "Cladiron-\(formatter.string(from: session.date))-\(short).fit"
    }

    /// Canonical DB++ ACTUAL JSON for a finished session.
    public static func canonicalJSON(for session: WorkoutSession) throws -> Data {
        if let reason = exportBlockers(for: session) { throw Failure.invalidWorkout(reason) }
        var workout = TrainingEngineBridge.workout(from: session, plans: planCandidates(for: session))
        if workout.endTime == nil {
            workout = Workout(
                schemaVersion: workout.schemaVersion, sessionId: workout.sessionId,
                startTime: workout.startTime,
                endTime: TrainingEngineBridge.timestampString(session.date),
                exercises: workout.exercises, planReference: workout.planReference)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let base = try? encoder.encode(workout),
              var root = (try? JSONSerialization.jsonObject(with: base)) as? [String: Any]
        else { throw Failure.serialization }

        // The FIT codec parses whole-second ISO-8601 timestamps (FIT itself is
        // second-resolution), so normalize before handing the document over.
        let wholeSeconds = ISO8601DateFormatter()
        root["startTime"] = wholeSeconds.string(from: session.date)
        root["endTime"] = wholeSeconds.string(from: session.endedAt ?? session.date)
        root["timezone"] = TimeZone.current.identifier
        if let notes = session.notes, !notes.isEmpty { root["notes"] = notes }
        if var exercises = root["exercises"] as? [[String: Any]] {
            let groups = ownerGroups(of: session)
            for index in exercises.indices where index < groups.count {
                guard var sets = exercises[index]["sets"] as? [[String: Any]] else { continue }
                for setIndex in sets.indices where setIndex < groups[index].count {
                    if let note = groups[index][setIndex].note, !note.isEmpty { sets[setIndex]["notes"] = note }
                }
                exercises[index]["sets"] = sets
            }
            root["exercises"] = exercises
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        else { throw Failure.serialization }
        return data
    }

    public static func export(session: WorkoutSession) throws -> ExportedFile {
        let json = try canonicalJSON(for: session)
        do {
            let fit = try GarminFITAdapter().exportActivity(workoutJSON: json)
            return ExportedFile(filename: filename(for: session), data: fit)
        } catch {
            throw Failure.serialization
        }
    }

    // MARK: Import preview

    public enum Fidelity: String, Equatable, Sendable { case lossless }

    public struct Preview: Equatable, Sendable {
        public let sourceFilename: String
        public let sessionID: UUID
        public let start: Date
        public let end: Date?
        public let exerciseCount: Int
        public let setCount: Int
        public let fidelity: Fidelity
        public let warnings: [String]
        let canonical: Data
    }

    /// Strict decode + validation. Pure and `Sendable`, so callers run it off
    /// the main actor. Never touches persistence.
    public static func preview(data: Data, filename: String) throws -> Preview {
        guard data.count <= maxFileBytes else { throw Failure.tooLarge }
        guard data.count >= 14, data[8..<12].elementsEqual(Array(".FIT".utf8)) else { throw Failure.notFIT }
        if Task.isCancelled { throw Failure.cancelled }
        let canonical: Data
        do {
            canonical = try GarminFITAdapter().importActivity(data, mode: .strict)
        } catch let error as HealthInteropError {
            switch error {
            case .lossyImport: throw Failure.sidecarRequired
            case .invalidEnvelope(let message) where message.contains("not a FIT"): throw Failure.notFIT
            default: throw Failure.invalidSidecar
            }
        } catch {
            throw Failure.malformed
        }
        if Task.isCancelled { throw Failure.cancelled }
        let parsed = try parse(canonical)
        return Preview(sourceFilename: filename, sessionID: parsed.id, start: parsed.start, end: parsed.end,
                       exerciseCount: parsed.exercises.count,
                       setCount: parsed.exercises.reduce(0) { $0 + $1.sets.count },
                       fidelity: .lossless, warnings: parsed.warnings, canonical: canonical)
    }

    /// Off-main-actor wrapper; cancellation surfaces as `.cancelled`.
    public static func previewOffMain(data: Data, filename: String) async throws -> Preview {
        let task = Task.detached(priority: .userInitiated) { try preview(data: data, filename: filename) }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    public static func existingSession(for preview: Preview, in context: ModelContext) -> WorkoutSession? {
        let all = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        return all.first { $0.id == preview.sessionID && $0.deletedAt == nil }
    }

    // MARK: Atomic apply

    public enum DuplicateDecision: Equatable, Sendable { case cancel, keepBoth, replace }

    public struct Receipt: Equatable, Sendable {
        public let importedSessionID: UUID
        public let replacedSessionID: UUID?
    }

    /// Writes the previewed workout in one save. On any failure the context is
    /// rolled back so the store is unchanged. Returns nil when the user
    /// cancels a duplicate.
    @discardableResult
    public static func apply(_ preview: Preview, to context: ModelContext,
                             duplicate: DuplicateDecision = .cancel,
                             originDevice: String = "fit-import") throws -> Receipt? {
        let parsed = try parse(preview.canonical)
        let existing = existingSession(for: preview, in: context)
        var newID = parsed.id
        var notes = parsed.notes
        var replaced: UUID?
        if let existing {
            switch duplicate {
            case .cancel: return nil
            case .keepBoth:
                newID = UUID()
                let trace = "Imported from \(preview.sourceFilename) (original session ID \(parsed.id.uuidString))."
                notes = [notes, trace].compactMap { $0 }.joined(separator: "\n")
            case .replace:
                replaced = existing.id
            }
        }
        do {
            if let existing {
                if duplicate == .replace {
                    for set in existing.sets ?? [] { context.delete(set) }
                    context.delete(existing)
                }
            }
            let session = WorkoutSession(id: newID, title: parsed.title, date: parsed.start,
                                         endedAt: parsed.end ?? parsed.start, notes: notes,
                                         isLogged: true, originDevice: originDevice)
            context.insert(session)
            let library = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
            var resolved: [Exercise] = []
            var order = 0
            for item in parsed.exercises {
                let exercise = library.first { item.exerciseID != nil && $0.sourceExerciseID == item.exerciseID }
                    ?? resolved.first { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }
                    ?? library.first { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }
                    ?? {
                        let created = Exercise(name: item.name, isCustom: item.exerciseID == nil,
                                               originDevice: originDevice, sourceExerciseID: item.exerciseID)
                        context.insert(created)
                        resolved.append(created)
                        return created
                    }()
                for set in item.sets {
                    order += 1
                    let entry = SetEntry(weight: set.loadKg, reps: set.reps, order: order,
                                         isWarmup: set.isWarmup, rpe: set.rpe, note: set.note,
                                         completedAt: parsed.end ?? parsed.start,
                                         originDevice: originDevice, session: session, exercise: exercise)
                    context.insert(entry)
                }
            }
            try context.save()
            return Receipt(importedSessionID: newID, replacedSessionID: replaced)
        } catch {
            context.rollback()
            throw Failure.writeFailed
        }
    }

    /// Undo a just-applied import of a brand-new session (not a replace).
    public static func undo(_ receipt: Receipt, in context: ModelContext) throws {
        guard receipt.replacedSessionID == nil else { throw Failure.writeFailed }
        let all = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        guard let session = all.first(where: { $0.id == receipt.importedSessionID }) else { return }
        for set in session.sets ?? [] { context.delete(set) }
        context.delete(session)
        do { try context.save() } catch { context.rollback(); throw Failure.writeFailed }
    }

    // MARK: Canonical ACTUAL parsing

    struct ParsedSet { let reps: Int; let loadKg: Double; let isWarmup: Bool; let rpe: Double?; let note: String? }
    struct ParsedExercise { let exerciseID: String?; let name: String; let sets: [ParsedSet] }
    struct Parsed {
        let id: UUID; let start: Date; let end: Date?; let title: String; let notes: String?
        let exercises: [ParsedExercise]; let warnings: [String]
    }

    static func parse(_ canonical: Data) throws -> Parsed {
        guard canonical.count <= maxCanonicalBytes,
              let root = (try? JSONSerialization.jsonObject(with: canonical)) as? [String: Any],
              let idText = root["sessionId"] as? String, let id = UUID(uuidString: idText),
              let startText = root["startTime"] as? String, let start = parseDate(startText),
              let rawExercises = root["exercises"] as? [[String: Any]]
        else { throw Failure.invalidSidecar }
        let end = (root["endTime"] as? String).flatMap(parseDate)
        if let end, end < start { throw Failure.invalidSidecar }
        var warnings: [String] = []
        var exercises: [ParsedExercise] = []
        for raw in rawExercises {
            let exerciseID = raw["exerciseId"] as? String
            guard let name = (raw["exerciseName"] as? String) ?? exerciseID, !name.isEmpty else {
                throw Failure.invalidSidecar
            }
            var sets: [ParsedSet] = []
            for rawSet in raw["sets"] as? [[String: Any]] ?? [] {
                let reps = (rawSet["reps"] as? NSNumber)?.intValue ?? 0
                guard reps >= 0 else { throw Failure.invalidSidecar }
                var kg = 0.0
                if let load = rawSet["load"] as? [String: Any], let value = (load["value"] as? NSNumber)?.doubleValue {
                    switch (load["unit"] as? String)?.lowercased() {
                    case "kg": kg = value
                    case "lb", "lbs": kg = value * 0.45359237
                    default: warnings.append("Unknown load unit for \(name); load ignored.")
                    }
                }
                guard kg >= 0, kg.isFinite else { throw Failure.invalidSidecar }
                sets.append(ParsedSet(reps: reps, loadKg: kg, isWarmup: (rawSet["setType"] as? String) == "warmup",
                                      rpe: (rawSet["rpe"] as? NSNumber)?.doubleValue,
                                      note: rawSet["notes"] as? String))
            }
            exercises.append(ParsedExercise(exerciseID: exerciseID, name: name, sets: sets))
        }
        guard exercises.contains(where: { !$0.sets.isEmpty }) else { throw Failure.invalidSidecar }
        return Parsed(id: id, start: start, end: end, title: "Imported FIT workout",
                      notes: root["notes"] as? String, exercises: exercises, warnings: warnings)
    }

    private static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    private static func ownerGroups(of session: WorkoutSession) -> [[SetEntry]] {
        var groups: [[SetEntry]] = []
        var indices: [UUID: Int] = [:]
        for set in session.orderedSets where set.isOwnerSet {
            guard let exercise = set.exercise else { continue }
            if let index = indices[exercise.id] { groups[index].append(set) }
            else { indices[exercise.id] = groups.count; groups.append([set]) }
        }
        return groups
    }

    private static func planCandidates(for session: WorkoutSession) -> [FreeExerciseDBPlusPlus.WorkoutPlan] {
        guard let data = session.enginePlanJSON,
              let plan = try? JSONDecoder().decode(FreeExerciseDBPlusPlus.WorkoutPlan.self, from: data)
        else { return [] }
        return [plan]
    }
}
