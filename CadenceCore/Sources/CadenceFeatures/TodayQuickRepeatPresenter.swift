import Foundation
import CadenceCore

/// A quick "repeat last workout" option for Today. Never competes with an
/// active/resumable session — the caller is the single source of truth for
/// that, this type just decides what (if anything) to show once it's clear.
public struct TodayQuickRepeatDisplay: Equatable, Sendable {
    public let sessionID: UUID
    public let title: String
}

public enum TodayQuickRepeatPresenter {
    public static func make(sessions: [WorkoutSession], hasActiveOrResumableSession: Bool) -> TodayQuickRepeatDisplay? {
        guard !hasActiveOrResumableSession else { return nil }
        guard let session = PreviousWorkoutPickerPolicy.candidates(sessions: sessions).first else { return nil }
        let name = session.title.isEmpty ? String(localized: "Workout", bundle: .module) : session.title
        let day = session.date.formatted(.dateTime.weekday(.abbreviated))
        return TodayQuickRepeatDisplay(sessionID: session.id,
                                        title: String(localized: "Repeat: \(name) — \(day)", bundle: .module))
    }
}
