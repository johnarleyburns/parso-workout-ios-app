import Foundation
import CadenceCore

// Watch redesign (plans/watch-redesign/2026-09-30/DESIGN.md §3/§5 S1–S5): the Set Card — two big
// pre-filled numbers, progress dots, one button. Pure state so the watch view only maps it.

/// One progress dot: logged, the set you're on, or still to come in the plan.
public enum WatchSetDot: Equatable, Sendable {
    case done, current, upcoming
}

/// Which number the Digital Crown adjusts (decision D-W4: weight by default).
public enum WatchSetCardField: Equatable, Sendable {
    case weight, reps
}

/// A coach or plan explanation shown under the numbers. `citationIDs` is empty only for plain plan
/// facts ("Planned · +2.5 vs last time"); any science claim carries its citations (HARD RULE).
public struct WatchCoachLine: Equatable, Sendable {
    public let text: String
    public let citationIDs: [String]

    public init(text: String, citationIDs: [String]) {
        self.text = text
        self.citationIDs = citationIDs
    }
}

public struct WatchSetCardState: Equatable, Sendable {
    public let exerciseName: String
    public let dots: [WatchSetDot]
    /// Weight in the user's display unit, formatted ("100", "102.5").
    public let weightText: String
    public let unitText: String
    public let reps: Int
    /// "Last time 97.5 × 5 · RPE 8", or nil for a first-ever set.
    public let lastTimeText: String?
    /// "Log set", or the echoed values once they differ from the prefill ("Log 100 × 4").
    public let logTitle: String
    public let echoesChange: Bool
    public let planLine: WatchCoachLine?
    /// "Sam · then you" when partners rotate (S4), else nil.
    public let lifterText: String?
    /// "RPE 9" / "RIR 2" when effort is set.
    public let effortText: String?
    public let isWarmup: Bool
}

/// Builds the Set Card from primitive inputs; host-tested.
public enum WatchSetCardBuilder {
    public struct LastTime: Equatable, Sendable {
        public let weightKg: Double
        public let reps: Int
        public let rpe: Double?

        public init(weightKg: Double, reps: Int, rpe: Double?) {
            self.weightKg = weightKg
            self.reps = reps
            self.rpe = rpe
        }
    }

    public static func make(exerciseName: String,
                            plannedWorkingSets: [PlannedSetPrescription],
                            completedWorkingSets: Int,
                            currentWeightKg: Double,
                            currentReps: Int,
                            prefillWeightKg: Double,
                            prefillReps: Int,
                            lastTime: LastTime?,
                            unit: MeasurementUnitPreference,
                            lifter: String?,
                            nextLifter: String?,
                            effortText: String?,
                            isWarmup: Bool) -> WatchSetCardState {
        let dots = makeDots(planned: plannedWorkingSets.count, completed: completedWorkingSets)
        let weightText = Format.weightValue(currentWeightKg, unit: unit, decimals: 1)
        let changed = abs(currentWeightKg - prefillWeightKg) > 0.001 || currentReps != prefillReps
        let logTitle = changed
            ? String(localized: "Log \(weightText) × \(currentReps)", bundle: .module)
            : String(localized: "Log set", bundle: .module)
        let last = lastTime.map { last -> String in
            let base = Format.previousShort(last.weightKg, reps: last.reps, unit: unit)
            if let rpe = last.rpe {
                return String(localized: "Last time \(base) · RPE \(Int(rpe.rounded()))", bundle: .module)
            }
            return String(localized: "Last time \(base)", bundle: .module)
        }
        let planned = plannedWorkingSets.indices.contains(completedWorkingSets)
            ? plannedWorkingSets[completedWorkingSets] : nil
        let lifterText: String?
        if let lifter {
            lifterText = nextLifter.map { String(localized: "\(lifter) · then \($0)", bundle: .module) } ?? lifter
        } else {
            lifterText = nil
        }
        return WatchSetCardState(
            exerciseName: exerciseName,
            dots: dots,
            weightText: weightText,
            unitText: unit.abbreviation,
            reps: currentReps,
            lastTimeText: last,
            logTitle: logTitle,
            echoesChange: changed,
            planLine: planLine(planned: planned, prefillWeightKg: prefillWeightKg, lastTime: lastTime,
                               unit: unit, isWarmup: isWarmup),
            lifterText: lifterText,
            effortText: effortText,
            isWarmup: isWarmup)
    }

    /// Done / current / upcoming. Without a plan there is one dot per logged set plus the current one.
    public static func makeDots(planned: Int, completed: Int) -> [WatchSetDot] {
        let total = max(planned, completed + 1)
        return (0..<total).map { index in
            if index < completed { return .done }
            if index == completed { return .current }
            return .upcoming
        }
    }

    /// The plan's explanation for this set, only when the prefill really came from the plan.
    /// - A target RPE is coach autoregulation → cites `rpeAutoregulation`.
    /// - A percentage of estimated max → cites `oneRMEstimation`.
    /// - Otherwise a plain plan fact ("Planned · +2.5 vs last time") with no science claim.
    static func planLine(planned: PlannedSetPrescription?, prefillWeightKg: Double, lastTime: LastTime?,
                         unit: MeasurementUnitPreference, isWarmup: Bool) -> WatchCoachLine? {
        guard let planned, !isWarmup else { return nil }
        let fromPlan = planned.targetWeightKg.map { abs($0 - prefillWeightKg) < 0.01 } ?? false
        if let percent = planned.oneRepMaxPercent, percent > 0, fromPlan {
            let value = Int((percent * (percent <= 1 ? 100 : 1)).rounded())
            return WatchCoachLine(text: String(localized: "Coach: \(value)% of your estimated max", bundle: .module),
                                  citationIDs: ["oneRMEstimation"])
        }
        if let rpe = planned.targetRPE, rpe > 0 {
            return WatchCoachLine(text: String(localized: "Coach: aim for RPE \(Int(rpe.rounded()))", bundle: .module),
                                  citationIDs: ["rpeAutoregulation"])
        }
        guard fromPlan, let target = planned.targetWeightKg, let last = lastTime, last.weightKg > 0 else { return nil }
        let delta = target - last.weightKg
        guard abs(delta) >= 0.01 else { return nil }
        let display = WorkoutMath.display(abs(delta), in: unit)
        let amount = Format.weightValue(WorkoutMath.canonical(display, from: unit), unit: unit, decimals: 1)
        let signed = delta > 0 ? "+\(amount)" : "−\(amount)"
        return WatchCoachLine(text: String(localized: "Planned · \(signed) \(unit.abbreviation) vs last time", bundle: .module),
                              citationIDs: [])
    }
}

extension WatchStrengthFlowModel {
    /// The working (non-warm-up) sets the plan asks of the current lifter for this exercise.
    public func plannedWorkingSets(for exercise: Exercise) -> [PlannedSetPrescription] {
        guard let session else { return [] }
        let sets = session.explicitPlannedSets(forPerformerID: currentPerformer?.id, exerciseName: exercise.name)
            ?? session.plannedPrescriptions(forPerformerID: currentPerformer?.id)
                .first { $0.exerciseName.caseInsensitiveCompare(exercise.name) == .orderedSame }?.sets
            ?? []
        return sets.filter { $0.kind != .warmup && !$0.isWarmup }
    }

    /// Working sets the current lifter has logged for this exercise in this workout.
    public func completedWorkingSets(for exercise: Exercise) -> Int {
        guard let session else { return 0 }
        return session.orderedSets.filter {
            $0.exercise?.id == exercise.id && !$0.isWarmup && belongsToCurrentPerformer($0)
        }.count
    }

    /// The Set Card for the exercise on the keypad, or nil outside the keypad.
    public var setCardState: WatchSetCardState? {
        guard case .keypad(let exercise) = stage else { return nil }
        let prior = priorSets(for: exercise).filter { !$0.isWarmup && belongsToCurrentPerformer($0) }
        let last = prior.last.map {
            WatchSetCardBuilder.LastTime(weightKg: $0.effectiveLoadKg, reps: $0.reps, rpe: $0.rpe)
        }
        let options = performerOptions
        let lifter = options.isEmpty ? nil : options.first { $0.index == currentPerformerIndex }?.name
        let nextLifter = options.isEmpty ? nil
            : options.first { $0.index == (currentPerformerIndex + 1) % options.count }?.name
        let effort = effortValue.map { "\(effortMode.displayName) \(Int($0.rounded()))" }
        return WatchSetCardBuilder.make(
            exerciseName: exercise.name,
            plannedWorkingSets: plannedWorkingSets(for: exercise),
            completedWorkingSets: completedWorkingSets(for: exercise),
            currentWeightKg: currentWeight,
            currentReps: Int(currentReps),
            prefillWeightKg: prefillWeightKg,
            prefillReps: Int(prefillReps),
            lastTime: last,
            unit: unit,
            lifter: lifter,
            nextLifter: options.count > 1 ? nextLifter : nil,
            effortText: effort,
            isWarmup: isWarmupSet)
    }

    /// Cycles the effort chip: none → 6 → 7 → 8 → 9 → 10 → none (S2).
    public func cycleEffort() {
        switch effortValue {
        case nil: effortValue = 6
        case let value? where value >= 10: effortValue = nil
        case let value?: effortValue = value + 1
        }
    }
}

extension Array {
    /// Bounds-checked element access for the watch flow.
    subscript(watchSafe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension WatchStrengthFlowModel {
    /// The exercise on the keypad (or waiting after rest), for Quick Talk's "current exercise".
    public var currentExerciseName: String? {
        if case .keypad(let exercise) = stage { return exercise.name }
        return exerciseList.last?.exercise.name
    }

    /// A planned exercise by name (case-insensitive).
    public func plannedExercise(named name: String) -> Exercise? {
        exerciseList.first { $0.exercise.name.caseInsensitiveCompare(name) == .orderedSame }?.exercise
    }

    /// Select a lifter by name; `nil` (or "Me") is the device owner.
    public func selectPerformer(named name: String?) {
        guard !performerOptions.isEmpty else { return }
        let match = performerOptions.first { option in
            guard let name else { return option.isMe }
            return option.name.caseInsensitiveCompare(name) == .orderedSame
        }
        if let match { selectPerformer(at: match.index) }
    }
}
