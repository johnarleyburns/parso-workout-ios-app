import Foundation
import SwiftData
import CadenceCore

extension WatchSync.CustomExercise {
    /// Order-independent fingerprint of a custom-exercise payload (ids, names,
    /// edit times). The phone replays its last application context on every
    /// WatchConnectivity activation, so the Watch sees the same list on nearly
    /// every launch; an unchanged fingerprint means there is nothing to store.
    public static func fingerprint(_ exercises: [WatchSync.CustomExercise]) -> String {
        let rows = exercises
            .map { "\($0.id.uuidString)|\($0.updatedAt.timeIntervalSince1970)|\($0.name)" }
            .sorted()
        // FNV-1a 64: deterministic across launches, unlike Swift's `Hasher`.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in rows.joined(separator: "\n").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return "\(exercises.count)-\(String(hash, radix: 16))"
    }
}

/// Upserts the phone's custom exercises into the Watch store.
///
/// The previous Watch implementation ran on the main actor and fetched the
/// entire exercise catalog (~900 rows) once per incoming exercise, rewrote
/// every row, and saved even when nothing changed. It ran at launch because
/// WatchConnectivity replays the last context on activation, which kept the
/// Watch unresponsive for seconds. This fetches once, indexes by id and by
/// case-insensitive name, writes only rows whose values differ, and saves only
/// when something changed. Callers run it on a background `ModelContext`.
public enum WatchCustomExerciseStore {
    /// Returns the number of inserted or updated exercises.
    @discardableResult
    public static func apply(_ incoming: [WatchSync.CustomExercise], in context: ModelContext) throws -> Int {
        guard !incoming.isEmpty else { return 0 }
        var byID: [UUID: Exercise] = [:]
        var byName: [String: Exercise] = [:]
        for exercise in try WorkoutRepository.allExercises(context) {
            byID[exercise.id] = exercise
            let key = exercise.name.lowercased()
            if byName[key] == nil { byName[key] = exercise }
        }

        var changed = 0
        for row in incoming {
            let existing = byID[row.id] ?? byName[row.name.lowercased()]
            if let existing, !differs(existing, from: row) { continue }
            let exercise = existing ?? Exercise(id: row.id, name: row.name, isCustom: true)
            if existing == nil {
                context.insert(exercise)
                byID[exercise.id] = exercise
                byName[row.name.lowercased()] = exercise
            }
            exercise.name = row.name
            exercise.isCustom = true
            exercise.category = row.category
            exercise.equipment = row.equipment
            exercise.mechanics = row.mechanics
            exercise.force = row.force
            exercise.primaryMuscles = row.primaryMuscles
            exercise.secondaryMuscles = row.secondaryMuscles
            exercise.searchKeywords = row.searchKeywords
            exercise.isLateral = row.isLateral
            exercise.updatedAt = row.updatedAt
            changed += 1
        }
        if changed > 0 { try context.save() }
        return changed
    }

    static func differs(_ exercise: Exercise, from row: WatchSync.CustomExercise) -> Bool {
        exercise.name != row.name
            || !exercise.isCustom
            || exercise.category != row.category
            || exercise.equipment != row.equipment
            || exercise.mechanics != row.mechanics
            || exercise.force != row.force
            || exercise.primaryMuscles != row.primaryMuscles
            || exercise.secondaryMuscles != row.secondaryMuscles
            || exercise.searchKeywords != row.searchKeywords
            || exercise.isLateral != row.isLateral
            || exercise.updatedAt != row.updatedAt
    }
}
