import Foundation

// Round 4 Part B — a concrete "prescribed work" model (round4b-plan.md §core).
// Pure value types: built-in catalogs (CrossFit benchmarks, strength presets)
// live in code as the single source of truth. A launched `WorkoutSession`
// remembers its plan via an additive `planKey` and resolves it here, so there is
// no SwiftData schema for plans and nothing to migrate.

/// Where a plan came from (decision: builtin catalogs only for v1; `.user` is
/// reserved for the future custom-plan store).
public enum PlanSource: String, Codable, Sendable {
    case crossfit, strengthPreset, user
}

/// The prescribed scheme — how the work is structured + timed.
public enum WorkoutScheme: Equatable, Sendable, Codable {
    /// `rounds` is a rep-ladder applied to every item each round (Fran = 21-15-9);
    /// `nil` means a single pass where each item carries its own `reps`.
    case forTime(rounds: [Int]?, timeCapSec: Int?)
    case amrap(minutes: Int)
    case emom(minutes: Int)
    case roundsForTime(count: Int, restSec: Int?)
    /// Plain strength (presets + custom builder, B-2): items carry target sets/reps.
    case strength
}

/// One prescribed movement within a plan.
public struct PlanItem: Equatable, Sendable, Codable, Identifiable {
    public let id: Int            // stable order
    public let movement: String   // must match an `ExerciseLibrary` name
    public let reps: Int?         // prescribed reps per round/pass
    public let distanceM: Double? // 400 m run, 1000 m row
    public let loadLb: Double?    // canonical Rx load (male), pounds
    public let loadLbFemale: Double?
    public let targetSets: Int?   // strength presets / custom
    public let note: String?      // "1.5/1 pood", "20/14 ball"

    public init(id: Int, movement: String, reps: Int? = nil, distanceM: Double? = nil,
                loadLb: Double? = nil, loadLbFemale: Double? = nil,
                targetSets: Int? = nil, note: String? = nil) {
        self.id = id
        self.movement = movement
        self.reps = reps
        self.distanceM = distanceM
        self.loadLb = loadLb
        self.loadLbFemale = loadLbFemale
        self.targetSets = targetSets
        self.note = note
    }
}

/// A concrete, prescribed workout (CrossFit benchmark, strength preset, or a
/// user's custom build).
public struct WorkoutPlan: Equatable, Sendable, Identifiable {
    public let id: String         // stable key: "fran", "preset-5x5"
    public let name: String
    public let source: PlanSource
    public let scheme: WorkoutScheme
    public let items: [PlanItem]
    public let notes: String?

    public init(id: String, name: String, source: PlanSource,
                scheme: WorkoutScheme, items: [PlanItem], notes: String? = nil) {
        self.id = id
        self.name = name
        self.source = source
        self.scheme = scheme
        self.items = items
        self.notes = notes
    }

    /// Movement names to pre-load into the session (first appearance order,
    /// de-duplicated so a movement used twice isn't double-listed).
    public var movementNames: [String] {
        var seen = Set<String>()
        return items.compactMap { seen.insert($0.movement).inserted ? $0.movement : nil }
    }

    /// A short, human display of the scheme ("21-15-9 for time", "AMRAP 20 min").
    public var schemeSummary: String {
        switch scheme {
        case let .forTime(rounds, cap):
            let base: String
            if let rounds, !rounds.isEmpty {
                base = rounds.map(String.init).joined(separator: "-") + " for time"
            } else {
                base = "For time"
            }
            if let cap { return base + " · cap \(Self.clock(cap))" }
            return base
        case let .amrap(min):
            return "AMRAP \(min) min"
        case let .emom(min):
            return "EMOM \(min) min"
        case let .roundsForTime(count, rest):
            let base = "\(count) rounds for time"
            if let rest, rest > 0 { return base + " · \(rest / 60) min rest" }
            return base
        case .strength:
            return "Strength"
        }
    }

    /// mm:ss for a second count.
    static func clock(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
}

// MARK: - CrossFit benchmark catalog ("The Girls")

/// The 15 classic CrossFit benchmark workouts with Rx loads (lb / pood-derived).
/// Sources: library.crossfit.com benchmark PDF; crossfit.com/crossfit-movements.
public enum BenchmarkWorkouts {
    public static let girls: [WorkoutPlan] = [
        WorkoutPlan(id: "fran", name: "Fran", source: .crossfit,
                    scheme: .forTime(rounds: [21, 15, 9], timeCapSec: nil),
                    items: [
                        PlanItem(id: 0, movement: "Thruster", loadLb: 95, loadLbFemale: 65),
                        PlanItem(id: 1, movement: "Pull-Up"),
                    ]),
        WorkoutPlan(id: "grace", name: "Grace", source: .crossfit,
                    scheme: .forTime(rounds: nil, timeCapSec: nil),
                    items: [PlanItem(id: 0, movement: "Clean and Jerk", reps: 30, loadLb: 135, loadLbFemale: 95)]),
        WorkoutPlan(id: "isabel", name: "Isabel", source: .crossfit,
                    scheme: .forTime(rounds: nil, timeCapSec: nil),
                    items: [PlanItem(id: 0, movement: "Snatch", reps: 30, loadLb: 135, loadLbFemale: 95)]),
        WorkoutPlan(id: "cindy", name: "Cindy", source: .crossfit,
                    scheme: .amrap(minutes: 20),
                    items: [
                        PlanItem(id: 0, movement: "Pull-Up", reps: 5),
                        PlanItem(id: 1, movement: "Push-Up", reps: 10),
                        PlanItem(id: 2, movement: "Air Squat", reps: 15),
                    ]),
        WorkoutPlan(id: "annie", name: "Annie", source: .crossfit,
                    scheme: .forTime(rounds: [50, 40, 30, 20, 10], timeCapSec: nil),
                    items: [
                        PlanItem(id: 0, movement: "Double-Under"),
                        PlanItem(id: 1, movement: "Sit-Up"),
                    ]),
        WorkoutPlan(id: "barbara", name: "Barbara", source: .crossfit,
                    scheme: .roundsForTime(count: 5, restSec: 180),
                    items: [
                        PlanItem(id: 0, movement: "Pull-Up", reps: 20),
                        PlanItem(id: 1, movement: "Push-Up", reps: 30),
                        PlanItem(id: 2, movement: "Sit-Up", reps: 40),
                        PlanItem(id: 3, movement: "Air Squat", reps: 50),
                    ], notes: "Rest precisely 3 minutes between rounds."),
        WorkoutPlan(id: "chelsea", name: "Chelsea", source: .crossfit,
                    scheme: .emom(minutes: 30),
                    items: [
                        PlanItem(id: 0, movement: "Pull-Up", reps: 5),
                        PlanItem(id: 1, movement: "Push-Up", reps: 10),
                        PlanItem(id: 2, movement: "Air Squat", reps: 15),
                    ], notes: "Each minute on the minute for 30 minutes."),
        WorkoutPlan(id: "diane", name: "Diane", source: .crossfit,
                    scheme: .forTime(rounds: [21, 15, 9], timeCapSec: nil),
                    items: [
                        PlanItem(id: 0, movement: "Deadlift", loadLb: 225, loadLbFemale: 155),
                        PlanItem(id: 1, movement: "Handstand Push-Up"),
                    ]),
        WorkoutPlan(id: "elizabeth", name: "Elizabeth", source: .crossfit,
                    scheme: .forTime(rounds: [21, 15, 9], timeCapSec: nil),
                    items: [
                        PlanItem(id: 0, movement: "Clean", loadLb: 135, loadLbFemale: 95),
                        PlanItem(id: 1, movement: "Ring Dip"),
                    ]),
        WorkoutPlan(id: "helen", name: "Helen", source: .crossfit,
                    scheme: .roundsForTime(count: 3, restSec: nil),
                    items: [
                        PlanItem(id: 0, movement: "Run", distanceM: 400),
                        PlanItem(id: 1, movement: "Kettlebell Swing", reps: 21, loadLb: 53, loadLbFemale: 35, note: "1.5/1 pood"),
                        PlanItem(id: 2, movement: "Pull-Up", reps: 12),
                    ]),
        WorkoutPlan(id: "jackie", name: "Jackie", source: .crossfit,
                    scheme: .forTime(rounds: nil, timeCapSec: nil),
                    items: [
                        PlanItem(id: 0, movement: "Rowing Machine", distanceM: 1000),
                        PlanItem(id: 1, movement: "Thruster", reps: 50, loadLb: 45, loadLbFemale: 45, note: "bar only"),
                        PlanItem(id: 2, movement: "Pull-Up", reps: 30),
                    ]),
        WorkoutPlan(id: "karen", name: "Karen", source: .crossfit,
                    scheme: .forTime(rounds: nil, timeCapSec: nil),
                    items: [PlanItem(id: 0, movement: "Wall Ball", reps: 150, loadLb: 20, loadLbFemale: 14, note: "20/14 ball")]),
        WorkoutPlan(id: "nancy", name: "Nancy", source: .crossfit,
                    scheme: .roundsForTime(count: 5, restSec: nil),
                    items: [
                        PlanItem(id: 0, movement: "Run", distanceM: 400),
                        PlanItem(id: 1, movement: "Overhead Squat", reps: 15, loadLb: 95, loadLbFemale: 65),
                    ]),
        WorkoutPlan(id: "angie", name: "Angie", source: .crossfit,
                    scheme: .forTime(rounds: nil, timeCapSec: nil),
                    items: [
                        PlanItem(id: 0, movement: "Pull-Up", reps: 100),
                        PlanItem(id: 1, movement: "Push-Up", reps: 100),
                        PlanItem(id: 2, movement: "Sit-Up", reps: 100),
                        PlanItem(id: 3, movement: "Air Squat", reps: 100),
                    ], notes: "Complete all reps of each movement before the next."),
        WorkoutPlan(id: "mary", name: "Mary", source: .crossfit,
                    scheme: .amrap(minutes: 20),
                    items: [
                        PlanItem(id: 0, movement: "Handstand Push-Up", reps: 5),
                        PlanItem(id: 1, movement: "Pistol Squat", reps: 10),
                        PlanItem(id: 2, movement: "Pull-Up", reps: 15),
                    ]),
    ]
}

// MARK: - Plan resolution

/// Resolves a `WorkoutSession.planKey` back to its plan across every built-in
/// catalog. Extended in B-2 to also search `StrengthPresets`.
public enum PlanCatalog {
    public static func plan(forKey key: String) -> WorkoutPlan? {
        BenchmarkWorkouts.girls.first { $0.id == key }
    }
}
