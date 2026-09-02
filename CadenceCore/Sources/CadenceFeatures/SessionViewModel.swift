import Foundation
import CadenceCore

/// Pure, session-derived computations lifted out of `SessionView` (test-pyramid
/// Phase 3): rep-ladder resolution, prescription lines, planned-only names,
/// last-weight defaulting, and load canonicalization. The view keeps `@Query` /
/// `@State` and the SwiftUI set table; it calls these for every derived value so
/// the rules are unit-tested headlessly instead of through XCUITest.
public enum SessionViewModel {

    /// Whether the set editor should default to a bodyweight set for an exercise.
    public static func isBodyweight(_ exercise: Exercise) -> Bool {
        exercise.equipmentValue == .bodyweight
    }

    /// Whether a set belongs to the given performer (nil ⇒ the owner / "Me").
    public static func setPerformedBy(_ set: SetEntry, performerID: UUID?) -> Bool {
        guard let performerID else { return set.isOwnerSet }
        return set.performedBy?.id == performerID
    }

    /// The effective rep-ladder for this session: the chosen scheme, or nil.
    public static func effectiveLadder(session: WorkoutSession) -> [Int]? {
        session.plannedRepLadder.isEmpty ? nil : session.plannedRepLadder
    }

    /// How many planned set rows an exercise should pre-seed (ladder length).
    public static func plannedSetCount(session: WorkoutSession) -> Int {
        effectiveLadder(session: session)?.count ?? 0
    }

    /// Planned exercise names from a reused workout that have no sets yet.
    public static func plannedOnlyNames(session: WorkoutSession) -> [String] {
        let logged = Set(session.exercisesInOrder.map(\.name))
        return session.plannedExerciseNames.filter { !logged.contains($0) }
    }

    /// Nothing logged or planned yet → offer "Use Previous Workout".
    public static func isEmptySession(session: WorkoutSession) -> Bool {
        session.exercisesInOrder.isEmpty && plannedOnlyNames(session: session).isEmpty
    }

    /// Whether `name` is a movement the coach prescribed for this session (P5.3) —
    /// the one the prescribed load pre-fills the keypad for.
    public static func isPrescribedMovement(_ name: String, session: WorkoutSession) -> Bool {
        session.prescribedLoadKg > 0 && session.plannedExerciseNames.contains(name)
    }

    /// The most recent weight logged for `exercise` by `performerID` in THIS session.
    public static func lastSessionWeight(session: WorkoutSession, exercise: Exercise,
                                         performerID: UUID?) -> Double? {
        session.orderedSets.reversed().first {
            $0.exercise?.id == exercise.id && setPerformedBy($0, performerID: performerID)
        }?.weight
    }

    /// Prescription line for a planned movement, resolved from the plan. A flexible
    /// template launched with a chosen rep scheme shows that ladder; a coach
    /// prescription also carries a working load.
    public static func prescription(for name: String, session: WorkoutSession,
                                    plan: WorkoutPlan?, unit: MeasurementUnitPreference) -> String? {
        let chosen = session.plannedRepLadder
        if let item = plan?.items.first(where: { $0.movement == name }) {
            let ladder = chosen.isEmpty ? nil : chosen
            let line = Format.prescription(item, ladder: ladder, unit: unit)
            return line.isEmpty ? nil : line
        }
        guard !chosen.isEmpty else { return nil }
        var line = chosen.map(String.init).joined(separator: "-") + " reps"
        if isPrescribedMovement(name, session: session), session.prescribedLoadKg > 0 {
            line += " @ \(Format.weight(session.prescribedLoadKg, unit: unit))"
        }
        return line
    }

    /// Default reps for the set at `setIndex`: the ladder rung if any, else a
    /// pattern guess from history, else the last-logged reps, else 5. Inputs are
    /// assembled by the view so the pattern-guess path is unit-testable.
    public static func plannedReps(ladder: [Int]?,
                                   setIndex: Int,
                                   currentSessionReps: [Int],
                                   priorSessionLadders: [[Int]],
                                   lastLoggedReps: Int?) -> Int {
        if let ladder, setIndex < ladder.count, ladder[setIndex] > 0 {
            return ladder[setIndex]
        }
        if setIndex > 0,
           let guess = RepPattern.guess(setIndex: setIndex,
                                        currentSessionReps: currentSessionReps,
                                        priorSessionLadders: priorSessionLadders) {
            return guess
        }
        return lastLoggedReps ?? 5
    }

    /// Parse a weight-entry string into canonical kilograms, optionally plate-rounded.
    public static func canonicalKg(input: String, unit: MeasurementUnitPreference,
                                   plateRounding: Bool) -> Double {
        let parsed = Double(input) ?? 0
        var kg = WorkoutMath.canonical(parsed, from: unit)
        if plateRounding { kg = UnitEntry.plateRounded(kg: kg, unit: unit) }
        return kg
    }

    /// Round only inferred loads before they reach the editor. Explicit plan
    /// loads remain exact; inferred pounds use the field-tested 5 lb increment
    /// and inferred kilograms use the matching 2.5 kg increment.
    public static func roundedInferredWeightKg(_ kg: Double,
                                               unit: MeasurementUnitPreference,
                                               basis: PerformerSetPlanner.WeightBasis) -> Double {
        guard kg > 0 else { return 0 }
        switch basis {
        case .explicitPlan, .ownerPlan:
            return kg
        case .exactHistory, .estimatedHistory, .priorHistory:
            let display = WorkoutMath.display(kg, in: unit)
            let increment = unit == .pounds ? 5.0 : 2.5
            return WorkoutMath.canonical((display / increment).rounded() * increment, from: unit)
        case .none:
            return 0
        }
    }
}
