import Foundation

/// Pure helpers for the first athlete-authored plan flow.
///
/// The UI deliberately builds the same unified `Plan` graph used by coach and
/// sharing paths. Keeping these mutations here makes the compact authoring
/// surface deterministic and gives the model a small, testable contract before
/// the richer item editors land.
public enum ManualPlanBuilder {
    public static let mondayFirst: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    public static func blankPlan(title: String = "My training week",
                                 now: Date = Date()) -> Plan {
        let days = mondayFirst.map { PlanDay(weekday: $0) }
        return Plan(title: title,
                    provenance: .selfAuthored,
                    horizon: .singleWeek,
                    weeks: [PlanWeek(index: 0, days: days)],
                    createdAt: now,
                    updatedAt: now,
                    authoredOnIdiom: .compact,
                    status: .active)
    }

    public static func strengthSession(title: String = "Strength session",
                                       now: Date = Date()) -> Session {
        Session(title: title, goal: .hypertrophy, status: .planned,
                note: nil, partners: [])
    }

    public static func strengthItem(exerciseKey: String,
                                    setCount: Int = 3,
                                    reps: Int = 8,
                                    order: Int = 0) -> StrengthItem {
        let count = max(1, setCount)
        let safeReps = max(1, reps)
        return StrengthItem(
            exerciseKey: ExerciseKey(raw: exerciseKey),
            order: max(0, order),
            sets: (0..<count).map { index in
                PrescribedSet(setIndex: index, repTarget: .exact(safeReps))
            })
    }

    public static func addSession(_ session: Session,
                                  to weekday: Weekday,
                                  in plan: inout Plan,
                                  now: Date = Date()) throws {
        guard var week = plan.weeks.first else {
            throw UnifiedPlanValidationError.planHasNoWeeks
        }
        guard let dayIndex = week.days.firstIndex(where: { $0.weekday == weekday }) else {
            throw UnifiedPlanValidationError.weekdaysMustBeMondayFirst
        }
        guard week.days[dayIndex].sessions.count < 2 else {
            throw UnifiedPlanValidationError.dayHasTooManySessions(weekday)
        }
        week.days[dayIndex].sessions.append(session)
        plan.weeks[0] = week
        plan.updatedAt = now
        try plan.validate()
    }

    public static func replaceSession(_ session: Session,
                                      in plan: inout Plan,
                                      now: Date = Date()) throws {
        guard var week = plan.weeks.first else {
            throw UnifiedPlanValidationError.planHasNoWeeks
        }
        for dayIndex in week.days.indices {
            if let sessionIndex = week.days[dayIndex].sessions.firstIndex(where: { $0.id == session.id }) {
                week.days[dayIndex].sessions[sessionIndex] = session
                plan.weeks[0] = week
                plan.updatedAt = now
                try plan.validate()
                return
            }
        }
        throw UnifiedPlanValidationError.emptySessionTitle
    }

    public static func removeSession(id: UUID,
                                     from plan: inout Plan,
                                     now: Date = Date()) throws {
        guard var week = plan.weeks.first else {
            throw UnifiedPlanValidationError.planHasNoWeeks
        }
        for dayIndex in week.days.indices {
            if let sessionIndex = week.days[dayIndex].sessions.firstIndex(where: { $0.id == id }) {
                week.days[dayIndex].sessions.remove(at: sessionIndex)
                plan.weeks[0] = week
                plan.updatedAt = now
                try plan.validate()
                return
            }
        }
    }
}
