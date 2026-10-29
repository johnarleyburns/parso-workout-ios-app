import Foundation
import SwiftData
import CadenceCore

/// Watch Lift → Strength source menu, Suggest review, and Previous templates.
/// Pure presenters; Suggest evaluates only the shared Coach snapshot (see `WatchSuggestResolver`).
public enum WatchLiftSources {
    public enum Source: String, CaseIterable, Sendable {
        case suggest, previous, custom
        public var title: String {
            switch self {
            case .suggest: "Suggest"
            case .previous: "Previous"
            case .custom: "Custom"
            }
        }
        public var systemImage: String {
            switch self {
            case .suggest: "sparkles"
            case .previous: "clock.arrow.circlepath"
            case .custom: "plus.circle.fill"
            }
        }
        public var accessibilityIdentifier: String { "watchStrength.\(rawValue)" }
        public var accessibilityLabel: String {
            switch self {
            case .suggest: "Suggest, the strength workout synced from iPhone"
            case .previous: "Previous, your last five strength workouts"
            case .custom: "Custom, choose reps, rest and partners"
            }
        }
        public var accessibilityHint: String {
            switch self {
            case .suggest: "Opens a review. Nothing starts until you confirm."
            case .previous: "Opens a list. Starting one creates a new workout from its template."
            case .custom: "Opens setup."
            }
        }
    }

    /// Rows shown before Prescriptions, in order.
    public static let menuOrder: [Source] = [.suggest, .previous, .custom]
    public static let menuTitle = "Lift"
    public static let previousLimit = 5
    public static let previewExerciseLimit = 3
}

/// What a Watch launch hands to `WatchStrengthView`.
public struct WatchLiftLaunch: Equatable, Sendable {
    public var title: String
    public var exerciseNames: [String]
    public var repLadder: [Int]
    public var planPayload: WatchPlanPayload?
}

public struct WatchPreviousWorkout: Equatable, Sendable, Identifiable {
    public static let emptyMessage = "Completed strength workouts will appear here after they sync."

    public var id: UUID
    public var title: String
    public var completedAt: Date
    public var exerciseCount: Int
    public var workingSetCount: Int
    /// Bounded preview names.
    public var previewNames: [String]
    /// Full structure for the detail view: "Bench Press · 3×8".
    public var structureLines: [String]
    public var launch: WatchLiftLaunch

    public var summary: String { "\(exerciseCount) exercises · \(workingSetCount) sets" }
    public var preview: String {
        previewNames.joined(separator: ", ") + (exerciseCount > previewNames.count ? "…" : "")
    }

    public static func completionDate(_ s: WorkoutSession) -> Date { s.endedAt ?? s.date }

    public static func isEligible(_ s: WorkoutSession) -> Bool {
        s.deletedAt == nil && !s.isResumable && s.completedOwnerWorkingSetCount > 0
    }

    /// Newest-first, at most `limit` eligible sessions. Ties break on start date then id.
    public static func list(from sessions: [WorkoutSession],
                            limit: Int = WatchLiftSources.previousLimit) -> [WatchPreviousWorkout] {
        guard limit > 0 else { return [] }
        let eligible = sessions.filter(isEligible).sorted {
            let a = completionDate($0), b = completionDate($1)
            if a != b { return a > b }
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
        return eligible.prefix(limit).compactMap(make)
    }

    /// Bounded read: newest sessions by start date, then filtered. Never mutates.
    public static func load(from context: ModelContext, scan: Int = 60) -> [WatchPreviousWorkout] {
        list(from: (try? WorkoutRepository.recentSessions(context, limit: scan)) ?? [])
    }

    static func make(_ s: WorkoutSession) -> WatchPreviousWorkout? {
        var names: [String] = []
        var repsByName: [String: [Int]] = [:]
        for set in s.orderedSets where !set.isWarmup && set.isOwnerSet && set.reps > 0 {
            let name = set.exerciseNameSnapshot ?? set.exercise?.name ?? ""
            guard !name.isEmpty else { continue }
            if repsByName[name] == nil { names.append(name) }
            repsByName[name, default: []].append(set.reps)
        }
        guard !names.isEmpty else { return nil }
        let prescriptions = names.map { name in
            PlannedExercisePrescription(
                exerciseName: name,
                sets: (repsByName[name] ?? []).map { PlannedSetPrescription(targetReps: $0) })
        }
        let title = s.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Strength" : s.title
        let ladder = repsByName[names[0]] ?? []
        let payload = WatchPlanPayload(
            title: title,
            strength: .init(exerciseNames: names, repLadder: ladder, prescriptions: prescriptions))
        return WatchPreviousWorkout(
            id: s.id, title: title, completedAt: completionDate(s),
            exerciseCount: names.count,
            workingSetCount: repsByName.values.reduce(0) { $0 + $1.count },
            previewNames: Array(names.prefix(WatchLiftSources.previewExerciseLimit)),
            structureLines: names.map { "\($0) · \(repsByName[$0]?.count ?? 0)×\(WatchSuggestReview.repsText(repsByName[$0] ?? []))" },
            launch: WatchLiftLaunch(title: title, exerciseNames: names, repLadder: ladder, planPayload: payload))
    }
}
