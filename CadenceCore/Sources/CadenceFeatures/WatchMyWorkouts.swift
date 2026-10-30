import Foundation
import CadenceCore

/// One row on the Watch "My Workouts" page.
public struct WatchMyWorkoutRow: Equatable, Sendable, Identifiable {
    public enum Status: Sendable, Equatable { case planned, completed }
    /// Typed identity of what a row opens; replaces parsing the string `id`.
    public enum Source: Sendable, Equatable {
        case planned(String)
        case strength(UUID)
        /// A phone-owned cardio workout mirrored to the Watch; read-only.
        case cardio(UUID)
    }
    public let id: String
    public let source: Source
    public let status: Status
    public let title: String
    /// Completed rows only; planned rows are today's plan.
    public let date: Date?
    /// Exercise names (planned) or logged working-set count (completed) summarised by the view.
    public let exerciseNames: [String]
    public let setCount: Int
    public let isCardio: Bool
    /// Cardio rows only.
    public let cardioType: String?
    public let durationSeconds: TimeInterval?
    public let distanceMeters: Double?
    /// Already-presentable "Imported from …" text, imported cardio rows only.
    public let originLabel: String?

    /// Strength rows show a set count; planned and cardio rows never show "0 sets".
    public var showsSetCount: Bool { source.isStrength }
}

extension WatchMyWorkoutRow {
    /// "32 min · 5.2 km" for cardio rows; nil parts are omitted and a row with neither is nil.
    public func cardioSummary(distanceUnit: DistanceUnitPreference) -> String? {
        var parts: [String] = []
        if let durationSeconds, durationSeconds >= 60 {
            parts.append("\(Int((durationSeconds / 60).rounded())) min")
        }
        if let distanceMeters, distanceMeters > 0 {
            let value = distanceUnit == .miles ? distanceMeters / 1609.344 : distanceMeters / 1000
            parts.append(String(format: "%.1f %@", value, distanceUnit.abbreviation))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension WatchMyWorkoutRow.Source {
    var isStrength: Bool { if case .strength = self { return true } else { return false } }
}

/// Builds the Watch "My Workouts" list: today's planned sessions first, then recent history.
public enum WatchMyWorkouts {
    public struct HistoryInput: Sendable {
        public let id: UUID
        public let title: String
        public let date: Date
        public let setCount: Int
        public init(id: UUID, title: String, date: Date, setCount: Int) {
            self.id = id; self.title = title; self.date = date; self.setCount = setCount
        }
    }

    /// A phone-mirrored cardio workout (see `WatchCardioHistoryRecord`).
    public struct CardioInput: Sendable {
        public let id: UUID
        public let title: String
        public let type: String
        public let start: Date
        public let end: Date?
        public let distanceMeters: Double?
        public let importLabel: String?
        public init(id: UUID, title: String, type: String, start: Date, end: Date? = nil,
                    distanceMeters: Double? = nil, importLabel: String? = nil) {
            self.id = id; self.title = title; self.type = type; self.start = start; self.end = end
            self.distanceMeters = distanceMeters; self.importLabel = importLabel
        }
    }

    /// Planned rows come first; completed strength and cardio rows are merged, sorted once
    /// newest-first (ties by id), and one shared `historyLimit` applies to the merged list.
    public static func rows(plan: WatchSync.TodayPlan?, history: [HistoryInput],
                            cardio: [CardioInput] = [], historyLimit: Int = 20) -> [WatchMyWorkoutRow] {
        let planned = (plan?.sessions ?? []).filter { $0.kind != .rest }.map {
            WatchMyWorkoutRow(id: "planned-\($0.id)", source: .planned($0.id), status: .planned,
                              title: $0.label.isEmpty ? ($0.kind == .strength ? "Strength" : "Cardio") : $0.label,
                              date: nil, exerciseNames: $0.exerciseNames, setCount: 0,
                              isCardio: $0.kind == .cardio, cardioType: nil, durationSeconds: nil,
                              distanceMeters: nil, originLabel: nil)
        }
        let strengthRows = history.map {
            WatchMyWorkoutRow(id: "done-\($0.id.uuidString)", source: .strength($0.id), status: .completed,
                              title: $0.title.isEmpty ? "Workout" : $0.title,
                              date: $0.date, exerciseNames: [], setCount: $0.setCount, isCardio: false,
                              cardioType: nil, durationSeconds: nil, distanceMeters: nil, originLabel: nil)
        }
        let cardioRows = cardio.map { item in
            WatchMyWorkoutRow(id: "cardio-\(item.id.uuidString)", source: .cardio(item.id), status: .completed,
                              title: item.title.isEmpty ? "Cardio" : item.title,
                              date: item.start, exerciseNames: [], setCount: 0, isCardio: true,
                              cardioType: item.type,
                              durationSeconds: item.end.map { max(0, $0.timeIntervalSince(item.start)) },
                              distanceMeters: item.distanceMeters, originLabel: item.importLabel)
        }
        let done = (strengthRows + cardioRows).sorted {
            let (a, b) = ($0.date ?? .distantPast, $1.date ?? .distantPast)
            return a != b ? a > b : $0.id < $1.id
        }.prefix(max(0, historyLimit))
        return planned + done
    }
}
