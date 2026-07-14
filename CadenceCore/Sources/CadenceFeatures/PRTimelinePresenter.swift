import Foundation
import CadenceCore

/// Prepares the Progress tab's PR-timeline rows for rendering (FR-5.2). Pure and
/// headless so the copy — "first-ever" vs "+5 kg over your last best" — is
/// `swift test`-verified. The view maps this to text + a Swift Charts series.
public enum PRTimelinePresenter {

    /// A semantic accent for a PR row. The view maps it to a `Color`;
    /// `CadenceFeatures` may not import SwiftUI.
    public enum Accent: String, Equatable, Sendable {
        case firstEver     // no prior best — a brand-new lift on the shelf
        case improvement   // beat a previous record
    }

    public struct Row: Equatable, Identifiable {
        public let id: UUID
        public let exerciseName: String
        public let kind: PRKind
        public let dateLabel: String       // "Mar 4"
        public let valueLabel: String      // "102 kg" / "128 kg e1RM" / "1,020 kg·reps"
        public let deltaLabel: String?     // "+5 kg over your last best" / nil for first-ever
        public let accent: Accent

        public init(id: UUID, exerciseName: String, kind: PRKind, dateLabel: String,
                    valueLabel: String, deltaLabel: String?, accent: Accent) {
            self.id = id
            self.exerciseName = exerciseName
            self.kind = kind
            self.dateLabel = dateLabel
            self.valueLabel = valueLabel
            self.deltaLabel = deltaLabel
            self.accent = accent
        }
    }

    /// Newest-first PR rows for the timeline list. `events` are ascending by date
    /// (from `PRTimeline.events`); we reverse for display.
    public static func rows(events: [PREvent],
                            unit: MeasurementUnitPreference,
                            calendar: Calendar = .current,
                            now: Date = Date()) -> [Row] {
        events.reversed().map { row(for: $0, unit: unit, calendar: calendar, now: now) }
    }

    public static func row(for e: PREvent,
                           unit: MeasurementUnitPreference,
                           calendar: Calendar = .current,
                           now: Date = Date()) -> Row {
        let accent: Accent = e.previous == nil ? .firstEver : .improvement
        return Row(id: e.id,
                   exerciseName: e.exerciseName,
                   kind: e.kind,
                   dateLabel: dateLabel(e.date, calendar: calendar, now: now),
                   valueLabel: valueLabel(e, unit: unit),
                   deltaLabel: deltaLabel(e, unit: unit),
                   accent: accent)
    }

    /// The record's value, unit-aware. Weight/e1RM render in the display unit;
    /// volume renders as unit-aware load × reps.
    static func valueLabel(_ e: PREvent, unit: MeasurementUnitPreference) -> String {
        switch e.kind {
        case .weight:
            return Format.weight(e.value, unit: unit, decimals: 0)
        case .e1RM:
            return "\(Format.weight(e.value, unit: unit, decimals: 0)) e1RM"
        case .volume:
            let displayVolume = WorkoutMath.display(e.value, in: unit)
            return "\(Int(displayVolume.rounded())) \(unit.abbreviation)\u{00b7}reps"
        }
    }

    /// The improvement over the previous best, or `nil` for a first-ever record.
    static func deltaLabel(_ e: PREvent, unit: MeasurementUnitPreference) -> String? {
        guard let previous = e.previous else { return nil }
        let delta = e.value - previous
        guard delta > 0 else { return nil }
        switch e.kind {
        case .weight, .e1RM:
            return "+\(Format.weight(delta, unit: unit, decimals: 0)) over your last best"
        case .volume:
            let displayDelta = WorkoutMath.display(delta, in: unit)
            return "+\(Int(displayDelta.rounded())) \(unit.abbreviation)\u{00b7}reps over your last best"
        }
    }

    static func dateLabel(_ date: Date, calendar: Calendar, now: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }
}
