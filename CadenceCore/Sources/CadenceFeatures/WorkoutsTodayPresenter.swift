import Foundation
import CadenceCore

/// Home's "Workouts Today" list: today's completed workouts plus the coach plan
/// still outstanding, as one ordered, renderable model. Pure so the badge
/// vocabulary, the ordering and the planned-volume arithmetic are unit-tested.
///
/// Field test 2026-08-18 #6: the rows used to be three flat, non-interactive
/// `HStack`s badged with the bare word `PLANNED`.
public enum WorkoutsTodayPresenter {

    /// Who authored a planned session. Only `.coach` is produced today; `.user`
    /// and `.trainer` exist so the badge needs no re-plumbing when self-created
    /// and trainer plans land (Cladiron Platform Spec v2.2).
    public enum PlanSource: String, Equatable, Sendable {
        case coach, user, trainer
        public var badgeText: String {
            switch self {
            case .coach: return "COACH'S PLAN"
            case .user: return "YOUR PLAN"
            case .trainer: return "TRAINER'S PLAN"
            }
        }
    }

    public enum Status: Equatable, Sendable {
        case completed
        case planned(PlanSource)
        public var badgeText: String {
            switch self {
            case .completed: return "COMPLETED"
            case .planned(let source): return source.badgeText
            }
        }
    }

    public enum Modality: Equatable, Sendable { case strength, cardio }

    /// One prescribed exercise inside an expanded planned row.
    public struct PlannedExerciseRow: Equatable, Sendable, Identifiable {
        public let name: String
        public let sets: Int
        public let repsText: String        // "12, 10, 8" or "8–12"
        public let loadKg: Double?         // nil ⇒ bodyweight or unknown (P3 rules)
        public let isBodyweight: Bool
        public var id: String { name }

        public init(name: String, sets: Int, repsText: String,
                    loadKg: Double?, isBodyweight: Bool) {
            self.name = name
            self.sets = sets
            self.repsText = repsText
            self.loadKg = loadKg
            self.isBodyweight = isBodyweight
        }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public let id: String
        public let status: Status
        public let modality: Modality
        public let title: String
        /// Second line when collapsed — exercise names, or the cardio modality.
        public let subtitle: String?
        /// Trailing value — "5 sets · 42m", "5.2 km · 31m", "12 sets · ~45m".
        public let value: String
        /// Expanded detail (planned rows only).
        public let why: String?
        public let exercises: [PlannedExerciseRow]
        public let plannedVolumeKg: Double?
        public let targetMinutes: Int?
        public let citationIds: [String]
        /// Navigation/launch key: the source workout id (completed) or the
        /// CoachSession id (planned).
        public let sourceKey: String
        public var isExpandable: Bool { status != .completed }
        public var isNavigable: Bool { status == .completed }
    }

    /// Completed first (newest first), then outstanding plan items in plan order.
    public static func rows(sessions: [WorkoutSession],
                            cardio: [CardioWorkout],
                            plannedToday: [CoachSession],
                            source: PlanSource = .coach,
                            now: Date = Date(),
                            calendar: Calendar = .current) -> [Row] {
        // Completed rows reuse This Week's presenter verbatim — the "what counts
        // as done today" rules live there and are not re-implemented here.
        let completed = TodayActivityPresenter
            .entries(sessions: sessions, cardio: cardio, now: now, calendar: calendar)
            .map { entry in
                Row(id: "completed.\(entry.sourceId.uuidString)",
                    status: .completed,
                    modality: entry.kind == .strength ? .strength : .cardio,
                    title: entry.title,
                    subtitle: entry.detail,
                    value: entry.value,
                    why: nil,
                    exercises: [],
                    plannedVolumeKg: nil,
                    targetMinutes: nil,
                    citationIds: [],
                    sourceKey: entry.sourceId.uuidString)
            }

        let planned = plannedToday
            .filter { $0.kind != .rest }
            .map { session -> Row in
                let isStrength = session.kind == .strength
                return Row(id: "planned.\(session.id)",
                           status: .planned(source),
                           modality: isStrength ? .strength : .cardio,
                           title: session.title,
                           subtitle: plannedSubtitle(session),
                           value: plannedValueText(session),
                           why: session.subtitle.isEmpty ? nil : session.subtitle,
                           exercises: plannedExercises(session),
                           plannedVolumeKg: plannedVolumeKg(session),
                           targetMinutes: session.durationMinutes,
                           citationIds: session.citationIds,
                           sourceKey: session.id)
            }

        return completed + planned
    }

    public static func plannedExercises(_ session: CoachSession) -> [PlannedExerciseRow] {
        (session.exercises ?? []).map { exercise in
            PlannedExerciseRow(
                name: exercise.name,
                sets: exercise.sets ?? exercise.repLadder?.count ?? 0,
                repsText: repsText(exercise),
                loadKg: exercise.loadKg,
                isBodyweight: ExerciseLoading.isBodyweight(named: exercise.name))
        }
    }

    /// Σ sets × reps × load over the prescription. nil when no exercise carries a
    /// load (a pure bodyweight plan has no meaningful tonnage).
    public static func plannedVolumeKg(_ session: CoachSession) -> Double? {
        var total: Double = 0
        for exercise in session.exercises ?? [] {
            guard let load = exercise.loadKg, load > 0 else { continue }
            let reps = repsPerSet(exercise)
            total += reps.reduce(0) { $0 + Double($1) * load }
        }
        return total > 0 ? total : nil
    }

    /// "12 sets · ~45m" for a planned strength session; "~30m easy" for cardio.
    public static func plannedValueText(_ session: CoachSession) -> String {
        let minutes = session.durationMinutes.map { "~\($0)m" }
        if session.kind == .strength {
            let sets = (session.exercises ?? []).reduce(0) { $0 + ($1.sets ?? $1.repLadder?.count ?? 0) }
            let setText = sets > 0 ? "\(sets) set\(sets == 1 ? "" : "s")" : nil
            return [setText, minutes].compactMap { $0 }.joined(separator: " · ")
        }
        let intensity = session.intensity?.rawValue
        return [minutes, intensity].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: - Helpers

    /// Collapsed second line: the exercise names for strength, the modality for
    /// cardio (there are no exercises to list).
    private static func plannedSubtitle(_ session: CoachSession) -> String? {
        let names = (session.exercises ?? []).map(\.name)
        if !names.isEmpty { return names.joined(separator: ", ") }
        if let modality = session.modality { return modality.rawValue.capitalized }
        return nil
    }

    private static func repsText(_ exercise: CoachSession.RecommendedExercise) -> String {
        if let ladder = exercise.repLadder, !ladder.isEmpty {
            return ladder.map(String.init).joined(separator: ", ")
        }
        switch (exercise.repsLow, exercise.repsHigh) {
        case let (low?, high?) where high > low: return "\(low)–\(high)"
        case let (low?, _): return "\(low)"
        case let (nil, high?): return "\(high)"
        default: return ""
        }
    }

    /// Reps for each planned set: the ladder when present, otherwise the low end
    /// of the rep range repeated across the set count. Volume is priced at the
    /// bottom of the range so the coach never over-promises tonnage.
    private static func repsPerSet(_ exercise: CoachSession.RecommendedExercise) -> [Int] {
        if let ladder = exercise.repLadder, !ladder.isEmpty { return ladder }
        guard let sets = exercise.sets, sets > 0 else { return [] }
        guard let reps = exercise.repsLow ?? exercise.repsHigh else { return [] }
        return Array(repeating: reps, count: sets)
    }
}
