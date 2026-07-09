import SwiftData
import CadenceCore

/// Background actor for off-main-thread export so the UI stays responsive.
/// Avoids iOS watchdog kills when working with large datasets.
@ModelActor
actor ExportActor {
    func buildExport(coachPreferences: ExportCoachPreferences?,
                     preferences: ExportPreferences?) throws -> CadenceExport {
        try WorkoutRepository.buildExport(modelContext,
                                          coachPreferences: coachPreferences,
                                          preferences: preferences)
    }
}
