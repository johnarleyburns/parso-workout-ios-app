import CadenceFeatures
import Foundation
import CadenceCore

/// Explicit reps belong to one workout and performer, across exercises.
public enum WorkoutEntryPreference {
    public static func reps(in session: WorkoutSession, performerID: UUID?) -> Int? {
        values(session)[performerID?.uuidString ?? "owner"]
    }

    public static func setReps(_ reps: Int, in session: WorkoutSession, performerID: UUID?) {
        guard (1...100).contains(reps) else { return }
        var overrides = values(session)
        overrides[performerID?.uuidString ?? "owner"] = reps
        if let data = try? JSONEncoder().encode(overrides) {
            session.setEntryRepOverridesJSON = String(decoding: data, as: UTF8.self)
        }
    }

    private static func values(_ session: WorkoutSession) -> [String: Int] {
        (try? JSONDecoder().decode([String: Int].self,
                                  from: Data(session.setEntryRepOverridesJSON.utf8))) ?? [:]
    }
}
