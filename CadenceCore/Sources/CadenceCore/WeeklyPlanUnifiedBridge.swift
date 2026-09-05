import Foundation

/// Converts the shipped coach-facing weekly projection into the unified value
/// graph. The bridge is intentionally pure: it gives the Home/Watch edge one
/// producer without moving SwiftData or UI concerns into the planning model.
public enum WeeklyPlanUnifiedBridge {
    public static func plan(from weeklyPlan: WeeklyPlan,
                            id: PlanID? = nil,
                            goal: TrainingGoal = .hypertrophy,
                            title: String = "Coach plan") -> Plan {
        let calendar = Calendar.current
        let weekStart = WeeklyStats.weekStart(now: weeklyPlan.generatedAt)
        let days = (0..<7).map { offset -> PlanDay in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let weekday = weekday(for: date, calendar: calendar)
            let outline = weeklyPlan.days.first { calendar.isDate($0.date, inSameDayAs: date) }
            return PlanDay(id: stableUUID("day|\(dateKey(date, calendar: calendar))"),
                           weekday: weekday,
                           sessions: outline?.sessions.map(session) ?? [])
        }
        let updatedAt = weeklyPlan.generatedAt
        return Plan(
            id: id ?? PlanID(raw: stableUUID("coach-plan|\(dateKey(weekStart, calendar: calendar))")),
            title: title,
            goal: goal,
            horizon: .singleWeek,
            weeks: [PlanWeek(id: stableUUID("week|\(dateKey(weekStart, calendar: calendar))"),
                             index: 0, days: days)],
            createdAt: weekStart,
            updatedAt: updatedAt,
            authoredOnIdiom: .regular,
            status: .active)
    }

    /// Converts one coach session using its existing stable string ID. This is
    /// also used by the Home edge to build the rich Watch payload for today.
    public static func session(_ planned: PlannedSession) -> Session {
        let items: [WorkoutItem]
        if planned.kind == .strength, let exercises = planned.exercises {
            items = exercises.enumerated().map { index, exercise in
                .strength(StrengthItem(
                    id: stableUUID("item|\(planned.id)|\(index)|\(exercise.name)"),
                    exerciseKey: ExerciseKey(raw: exerciseKey(for: exercise.name)),
                    order: index,
                    sets: sets(for: exercise, namespace: "\(planned.id)|\(index)")))
            }
        } else if planned.kind == .rest || planned.isRest {
            items = []
        } else {
            items = [.cardio(CardioItem(
                id: stableUUID("cardio|\(planned.id)"),
                order: 0,
                prescription: cardioPrescription(for: planned)))]
        }
        return Session(id: stableUUID("session|\(planned.id)"), title: planned.label,
                       goal: .hypertrophy, items: items,
                       estimatedDurationMinutes: planned.cardioDurationMinutes,
                       status: planned.sourceWorkoutId == nil ? .planned : .completed)
    }

    private static func sets(for exercise: CoachSession.RecommendedExercise,
                             namespace: String) -> [PrescribedSet] {
        let ladder = exercise.repLadder ?? []
        let count = max(exercise.sets ?? ladder.count, ladder.isEmpty ? 1 : ladder.count)
        return (0..<count).map { index in
            let reps = index < ladder.count ? ladder[index] : (exercise.repsLow ?? 1)
            let load: LoadPrescription = exercise.loadKg.map {
                .absoluteWeight(value: $0, unit: .kg)
            } ?? .unspecified
            return PrescribedSet(
                id: stableUUID("set|\(namespace)|\(exercise.name)|\(index)|\(reps)|\(exercise.loadKg ?? -1)"),
                setIndex: index,
                repTarget: .exact(reps),
                load: load,
                targetRIR: exercise.rir)
        }
    }

    private static func cardioPrescription(for planned: PlannedSession) -> CardioPrescription {
        let activity = cardioActivity(for: planned)
        let intensity = planned.cardioZone.map(CardioIntensity.heartRateZone)
        if planned.kind == .vo2Intervals {
            let work = IntervalSegment(durationSeconds: 60,
                                       intensity: intensity ?? .rpe(8...9))
            let recovery = IntervalSegment(durationSeconds: 120,
                                           intensity: .rpe(2...4))
            return .intervals(Intervals(activity: activity, rounds: 4,
                                        work: work, recovery: recovery))
        }
        return .steadyState(SteadyState(
            activity: activity,
            durationSeconds: planned.cardioDurationMinutes.map { $0 * 60 },
            intensity: intensity))
    }

    private static func cardioActivity(for planned: PlannedSession) -> CardioActivity {
        let label = planned.label.lowercased()
        if label.contains("run") { return .run }
        if label.contains("walk") { return .walk }
        if label.contains("cycle") || label.contains("bike") { return .bike }
        if label.contains("row") { return .row }
        if label.contains("swim") { return .swim }
        return .other(planned.label)
    }

    private static func exerciseKey(for name: String) -> String {
        ExerciseLibrary.template(matching: name)?.sourceExerciseID
            ?? ExerciseLibrary.lookupKey(name)
    }

    private static func weekday(for date: Date, calendar: Calendar) -> Weekday {
        switch calendar.component(.weekday, from: date) {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        default: return .saturday
        }
    }

    private static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// Stable, process-independent UUID for legacy string IDs that predate the
    /// unified graph. FNV-1a is sufficient here because this is identity
    /// namespacing, not a security or deduplication primitive.
    private static func stableUUID(_ value: String) -> UUID {
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 10_995_116_282_311_906_951
        for byte in value.utf8 {
            first ^= UInt64(byte)
            first &*= 1_099_511_628_211
            second ^= UInt64(byte &+ 31)
            second &*= 1_099_511_628_211
        }
        let hex = String(format: "%016llx%016llx", first, second)
        let chars = Array(hex)
        let groups = [8, 4, 4, 4, 12].reduce(into: ([String](), 0)) { result, length in
            result.0.append(String(chars[result.1..<(result.1 + length)]))
            result.1 += length
        }.0
        return UUID(uuidString: groups.joined(separator: "-")) ?? UUID()
    }
}
