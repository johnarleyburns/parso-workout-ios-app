import Foundation
import CadenceCore

/// Phase D (field-test-fixes): true today-list for "What you did."
/// Replaces the old `coachDecision.observedFacts` approach (≤1 entry per type)
/// with a complete list of today's actual workouts.
public enum TodayActivityPresenter {

    public enum EntryKind: Equatable {
        case strength
        case cardio
    }

    public struct Entry: Equatable, Identifiable {
        public let id: UUID
        public let kind: EntryKind
        public let title: String
        public let detail: String?
        public let value: String
        public let occurredAt: Date
        /// The source workout's UUID so the view can navigate to it.
        public let sourceId: UUID

        public init(id: UUID, kind: EntryKind, title: String, detail: String?,
                    value: String, occurredAt: Date, sourceId: UUID) {
            self.id = id
            self.kind = kind
            self.title = title
            self.detail = detail
            self.value = value
            self.occurredAt = occurredAt
            self.sourceId = sourceId
        }
    }

    /// Returns all completed (non-resumable) workouts from today, newest first,
    /// no cap.
    public static func entries(
        sessions: [WorkoutSession],
        cardio: [CardioWorkout],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Entry] {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: today)!

        let strengthEntries = sessions
            .filter { s in
                s.deletedAt == nil && !s.isResumable
                && s.endedAt != nil
                && s.date >= today && s.date < end
            }
            .map { s -> Entry in
                let exercises = s.exercisesInOrder.map(\.name)
                let detail = exercises.isEmpty ? nil : exercises.joined(separator: ", ")
                let duration = Self.formatDuration(s.duration)
                let setCount = s.orderedSets.count
                let value = setCount > 0 ? "\(setCount) set\(setCount == 1 ? "" : "s") · \(duration)" : duration
                return Entry(
                    id: s.id, kind: .strength,
                    title: s.title.isEmpty ? "Strength session" : s.title,
                    detail: detail,
                    value: value,
                    occurredAt: s.endedAt ?? s.date,
                    sourceId: s.id
                )
            }

        let cardioEntries = cardio
            .filter { c in
                c.deletedAt == nil
                && c.start >= today && c.start < end
            }
            .map { c -> (CardioWorkout, Entry) in
                let duration = formatDuration(c.duration)
                let value: String
                if let dist = c.distance, dist > 0 {
                    if dist >= 1000 { value = "\(String(format: "%.1f", dist / 1000)) km · \(duration)" }
                    else { value = "\(Int(dist)) m · \(duration)" }
                } else {
                    value = duration.isEmpty ? duration : duration
                }
                let badge: String
                if let hr = c.avgHeartRate, hr > 0 {
                    badge = "\(Int(hr)) bpm · "
                } else {
                    badge = c.type.isEmpty ? "" : "\(c.type) · "
                }
                return (c, Entry(
                    id: c.id, kind: .cardio,
                    title: badge + "Cardio",
                    detail: nil,
                    value: value,
                    occurredAt: c.start,
                    sourceId: c.id
                ))
            }

        var all = strengthEntries + cardioEntries.map { $0.1 }
        all.sort(by: { $0.occurredAt > $1.occurredAt })
        return all
    }

    // MARK: - Helpers

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let t = Int(max(0, interval))
        let h = t / 3600
        let m = (t % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "0m"
    }
}
