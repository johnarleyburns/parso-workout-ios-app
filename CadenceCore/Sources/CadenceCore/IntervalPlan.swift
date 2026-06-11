import Foundation

// Field-testing §06 — the interval engine that runs HIIT and boxing protocols
// for the user, plus the full-screen high-visibility color state. Pure and
// headless-testable; the app layer drives it against a WorkoutClock.

public enum IntervalPhaseKind: String, Codable, Sendable {
    case warmup, work, rest, cooldown
}

/// One phase in an expanded interval plan.
public struct IntervalPhase: Equatable, Sendable, Identifiable {
    public let id: Int
    public let kind: IntervalPhaseKind
    public let duration: TimeInterval
    public let label: String

    public init(id: Int, kind: IntervalPhaseKind, duration: TimeInterval, label: String) {
        self.id = id
        self.kind = kind
        self.duration = duration
        self.label = label
    }
}

/// A fully-expanded sequence of phases the runner walks through.
public struct IntervalPlan: Equatable, Sendable {
    public let name: String
    public let phases: [IntervalPhase]

    public init(name: String, phases: [IntervalPhase]) {
        self.name = name
        self.phases = phases
    }

    public var totalDuration: TimeInterval { phases.reduce(0) { $0 + $1.duration } }

    /// Locates the active phase for an elapsed time, with seconds left in it and
    /// overall. Returns nil once the plan is complete.
    public func state(atElapsed elapsed: TimeInterval) -> (index: Int, phase: IntervalPhase, phaseRemaining: TimeInterval, overallRemaining: TimeInterval)? {
        guard elapsed >= 0, !phases.isEmpty else { return nil }
        var acc: TimeInterval = 0
        for (i, p) in phases.enumerated() {
            if elapsed < acc + p.duration {
                let phaseRemaining = (acc + p.duration) - elapsed
                return (i, p, phaseRemaining, totalDuration - elapsed)
            }
            acc += p.duration
        }
        return nil // complete
    }

    public func isComplete(atElapsed elapsed: TimeInterval) -> Bool {
        elapsed >= totalDuration
    }

    // MARK: Factories (decisions #21/#22)

    /// Tabata: warmup → rounds × (work / rest) → cooldown. Classic = 8×(20/10).
    public static func tabata(warmup: TimeInterval = 300, rounds: Int = 8,
                              work: TimeInterval = 20, rest: TimeInterval = 10,
                              cooldown: TimeInterval = 300) -> IntervalPlan {
        var phases: [IntervalPhase] = []
        var id = 0
        func add(_ kind: IntervalPhaseKind, _ dur: TimeInterval, _ label: String) {
            if dur > 0 { phases.append(IntervalPhase(id: id, kind: kind, duration: dur, label: label)); id += 1 }
        }
        add(.warmup, warmup, "Warm Up")
        for r in 1...max(1, rounds) {
            add(.work, work, "Work · Round \(r)/\(rounds)")
            if r < rounds { add(.rest, rest, "Rest") } else { add(.rest, rest, "Rest") }
        }
        add(.cooldown, cooldown, "Cool Down")
        return IntervalPlan(name: "Tabata", phases: phases)
    }

    /// Norwegian 4×4: warmup → 4 × (4 min hard / 3 min recover) → cooldown.
    public static func norwegian4x4(warmup: TimeInterval = 600, rounds: Int = 4,
                                    work: TimeInterval = 240, recover: TimeInterval = 180,
                                    cooldown: TimeInterval = 300) -> IntervalPlan {
        var phases: [IntervalPhase] = []
        var id = 0
        func add(_ kind: IntervalPhaseKind, _ dur: TimeInterval, _ label: String) {
            if dur > 0 { phases.append(IntervalPhase(id: id, kind: kind, duration: dur, label: label)); id += 1 }
        }
        add(.warmup, warmup, "Warm Up")
        for r in 1...max(1, rounds) {
            add(.work, work, "Effort · \(r)/\(rounds)")
            if r < rounds { add(.rest, recover, "Recover") }
        }
        add(.cooldown, cooldown, "Cool Down")
        return IntervalPlan(name: "Norwegian 4×4", phases: phases)
    }

    /// Boxing rounds: rounds × (round work / rest between).
    public static func boxing(rounds: Int = 12, round: TimeInterval = 180,
                              rest: TimeInterval = 60) -> IntervalPlan {
        var phases: [IntervalPhase] = []
        var id = 0
        for r in 1...max(1, rounds) {
            phases.append(IntervalPhase(id: id, kind: .work, duration: round, label: "Round \(r)/\(rounds)")); id += 1
            if r < rounds {
                phases.append(IntervalPhase(id: id, kind: .rest, duration: rest, label: "Rest")); id += 1
            }
        }
        return IntervalPlan(name: "Boxing", phases: phases)
    }

    /// Gibala method: rounds × (60s work / 60s rest), ~20 min total.
    public static func gibala(warmup: TimeInterval = 180, rounds: Int = 8,
                              work: TimeInterval = 60, rest: TimeInterval = 60,
                              cooldown: TimeInterval = 120) -> IntervalPlan {
        rounded(name: "Gibala", warmup: warmup, rounds: rounds, work: work,
                workLabel: { "Work · \($0)/\(rounds)" }, rest: rest, restLabel: "Rest",
                cooldown: cooldown)
    }

    /// Sprint Interval Training (Wingate): rounds × (30s all-out / 4 min recovery).
    public static func sit(warmup: TimeInterval = 180, rounds: Int = 4,
                           work: TimeInterval = 30, recover: TimeInterval = 240,
                           cooldown: TimeInterval = 180) -> IntervalPlan {
        rounded(name: "SIT (Wingate)", warmup: warmup, rounds: rounds, work: work,
                workLabel: { "Sprint · \($0)/\(rounds)" }, rest: recover, restLabel: "Recover",
                cooldown: cooldown)
    }

    /// REHIT: warm-up → 2 × (20s all-out / 3 min recovery) → cool-down.
    public static func rehit(warmup: TimeInterval = 120, rounds: Int = 2,
                             work: TimeInterval = 20, recover: TimeInterval = 180,
                             cooldown: TimeInterval = 120) -> IntervalPlan {
        rounded(name: "REHIT", warmup: warmup, rounds: rounds, work: work,
                workLabel: { "Sprint · \($0)/\(rounds)" }, rest: recover, restLabel: "Recover",
                cooldown: cooldown)
    }

    /// 10-20-30: sets × ( reps × (30s easy / 20s moderate / 10s sprint) ) with a
    /// 2-minute recovery between sets.
    public static func tenTwentyThirty(warmup: TimeInterval = 300, sets: Int = 3,
                                       reps: Int = 5, recover: TimeInterval = 120,
                                       cooldown: TimeInterval = 120) -> IntervalPlan {
        var phases: [IntervalPhase] = []
        var id = 0
        func add(_ kind: IntervalPhaseKind, _ dur: TimeInterval, _ label: String) {
            if dur > 0 { phases.append(IntervalPhase(id: id, kind: kind, duration: dur, label: label)); id += 1 }
        }
        add(.warmup, warmup, "Warm Up")
        for set in 1...max(1, sets) {
            for _ in 1...max(1, reps) {
                add(.rest, 30, "Easy")
                add(.work, 20, "Moderate")
                add(.work, 10, "Sprint!")
            }
            if set < sets { add(.rest, recover, "Recover · set \(set)/\(sets)") }
        }
        add(.cooldown, cooldown, "Cool Down")
        return IntervalPlan(name: "10-20-30", phases: phases)
    }

    /// Shared builder: warmup → rounds × (work, then rest BETWEEN rounds) → cooldown.
    private static func rounded(name: String, warmup: TimeInterval, rounds: Int,
                                work: TimeInterval, workLabel: (Int) -> String,
                                rest: TimeInterval, restLabel: String,
                                cooldown: TimeInterval) -> IntervalPlan {
        var phases: [IntervalPhase] = []
        var id = 0
        func add(_ kind: IntervalPhaseKind, _ dur: TimeInterval, _ label: String) {
            if dur > 0 { phases.append(IntervalPhase(id: id, kind: kind, duration: dur, label: label)); id += 1 }
        }
        add(.warmup, warmup, "Warm Up")
        for r in 1...max(1, rounds) {
            add(.work, work, workLabel(r))
            if r < rounds { add(.rest, rest, restLabel) }
        }
        add(.cooldown, cooldown, "Cool Down")
        return IntervalPlan(name: name, phases: phases)
    }

    /// Fully custom: warmup → rounds × (work / rest) → cooldown.
    public static func custom(name: String = "Custom", warmup: TimeInterval, rounds: Int,
                              work: TimeInterval, rest: TimeInterval, cooldown: TimeInterval) -> IntervalPlan {
        var phases: [IntervalPhase] = []
        var id = 0
        func add(_ kind: IntervalPhaseKind, _ dur: TimeInterval, _ label: String) {
            if dur > 0 { phases.append(IntervalPhase(id: id, kind: kind, duration: dur, label: label)); id += 1 }
        }
        add(.warmup, warmup, "Warm Up")
        for r in 1...max(1, rounds) {
            add(.work, work, "Work · Round \(r)/\(rounds)")
            if r < rounds { add(.rest, rest, "Rest") }
        }
        add(.cooldown, cooldown, "Cool Down")
        return IntervalPlan(name: name, phases: phases)
    }
}

/// The whole-screen color signal (field-testing §06, decision #20) — readable
/// from across the room. Meaning is also carried by label + icon so it never
/// relies on color alone (NFR-2 / color-blind support).
public enum FullScreenColorState: String, Equatable, Sendable {
    case work, warning, imminent, rest, neutral
}

public enum IntervalSignal {
    /// Thresholds: work >30s green, ≤30s warning, ≤3s imminent (flashing),
    /// rest red, warmup/cooldown neutral.
    public static func colorState(phase: IntervalPhaseKind, remaining: TimeInterval) -> FullScreenColorState {
        switch phase {
        case .rest: return .rest
        case .warmup, .cooldown: return .neutral
        case .work:
            if remaining <= 3 { return .imminent }
            if remaining <= 30 { return .warning }
            return .work
        }
    }
}
