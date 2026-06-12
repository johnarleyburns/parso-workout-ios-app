import Foundation

/// A pure, formatting-free value describing a finished workout, built from
/// either a strength `WorkoutSession` or a `CardioWorkout` (field-testing
/// Round 4 A3). The view layer owns all `String` formatting (`Format.*`,
/// `CardioMath.formatPace`); this type only carries raw typed fields so it is
/// `swift test`-able and never leaks `@Model` rows.
///
/// For a strength session the cardio fields (`distanceM`, `paceSecPerKm`,
/// `calories`, `avgHR`, `maxHR`, `hr`, `route`) are nil/empty; for a cardio
/// workout the strength fields (`totalVolumeKg`, `exercises`) are nil/empty.
public struct WorkoutSummaryData: Equatable, Sendable {
    public enum Kind: String, Sendable { case strength, cardio }

    /// One exercise's roll-up within a strength summary. Reflects the **owner's
    /// working (non-warmup) sets only** — partner and warmup sets are excluded
    /// (field-testing §04, decision #13), matching `WorkoutSession.totalVolume`.
    public struct ExerciseLine: Equatable, Sendable {
        public let name: String
        public let setCount: Int
        /// Heaviest owner working-set weight (kg) for this exercise, if any.
        public let topSetWeightKg: Double?
        /// Reps of each owner working set, in logged order.
        public let reps: [Int]

        public init(name: String, setCount: Int, topSetWeightKg: Double?, reps: [Int]) {
            self.name = name
            self.setCount = setCount
            self.topSetWeightKg = topSetWeightKg
            self.reps = reps
        }
    }

    public let kind: Kind
    public let title: String
    public let date: Date
    public let durationSec: TimeInterval
    public let distanceM: Double?
    public let paceSecPerKm: Double?
    public let calories: Double?
    public let avgHR: Double?
    public let maxHR: Double?
    public let totalVolumeKg: Double?        // strength
    public let setCount: Int                 // strength: owner working-set count
    public let exercises: [ExerciseLine]     // strength
    public let hr: [(t: TimeInterval, bpm: Double)]   // cardio chart
    public let route: [(lat: Double, lon: Double)]    // cardio map

    public init(kind: Kind,
                title: String,
                date: Date,
                durationSec: TimeInterval,
                distanceM: Double? = nil,
                paceSecPerKm: Double? = nil,
                calories: Double? = nil,
                avgHR: Double? = nil,
                maxHR: Double? = nil,
                totalVolumeKg: Double? = nil,
                setCount: Int = 0,
                exercises: [ExerciseLine] = [],
                hr: [(t: TimeInterval, bpm: Double)] = [],
                route: [(lat: Double, lon: Double)] = []) {
        self.kind = kind
        self.title = title
        self.date = date
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.paceSecPerKm = paceSecPerKm
        self.calories = calories
        self.avgHR = avgHR
        self.maxHR = maxHR
        self.totalVolumeKg = totalVolumeKg
        self.setCount = setCount
        self.exercises = exercises
        self.hr = hr
        self.route = route
    }

    // Tuple-typed arrays block Equatable synthesis, so compare element-wise.
    public static func == (lhs: WorkoutSummaryData, rhs: WorkoutSummaryData) -> Bool {
        lhs.kind == rhs.kind
            && lhs.title == rhs.title
            && lhs.date == rhs.date
            && lhs.durationSec == rhs.durationSec
            && lhs.distanceM == rhs.distanceM
            && lhs.paceSecPerKm == rhs.paceSecPerKm
            && lhs.calories == rhs.calories
            && lhs.avgHR == rhs.avgHR
            && lhs.maxHR == rhs.maxHR
            && lhs.totalVolumeKg == rhs.totalVolumeKg
            && lhs.setCount == rhs.setCount
            && lhs.exercises == rhs.exercises
            && lhs.hr.count == rhs.hr.count
            && zip(lhs.hr, rhs.hr).allSatisfy { $0 == $1 }
            && lhs.route.count == rhs.route.count
            && zip(lhs.route, rhs.route).allSatisfy { $0 == $1 }
    }

    // MARK: Builders

    /// Builds a strength summary from a finished (or in-progress) session.
    /// Cardio fields are nil; `exercises`/`setCount`/`totalVolumeKg` reflect the
    /// owner's working sets only.
    public static func from(session: WorkoutSession) -> WorkoutSummaryData {
        let exercises: [ExerciseLine] = session.exercisesInOrder.compactMap { ex in
            let working = session.orderedSets.filter {
                $0.exercise?.id == ex.id && $0.isOwnerSet && !$0.isWarmup
            }
            guard !working.isEmpty else { return nil }
            let top = working.map(\.weight).max()
            return ExerciseLine(name: ex.name,
                                setCount: working.count,
                                topSetWeightKg: top,
                                reps: working.map(\.reps))
        }
        let setCount = exercises.reduce(0) { $0 + $1.setCount }
        return WorkoutSummaryData(
            kind: .strength,
            title: session.title,
            date: session.date,
            durationSec: session.duration,
            totalVolumeKg: session.totalVolume,
            setCount: setCount,
            exercises: exercises
        )
    }

    /// Builds a cardio summary from a recorded/ingested cardio workout.
    /// Strength fields are nil/empty; HR + route series are carried as plain
    /// tuples so no `@Model` rows escape the value.
    public static func from(cardio: CardioWorkout) -> WorkoutSummaryData {
        let pace: Double? = cardio.distance.flatMap {
            CardioMath.paceSecPerKm(distanceMeters: $0, seconds: cardio.duration)
        }
        return WorkoutSummaryData(
            kind: .cardio,
            title: cardio.typeValue.displayName,
            date: cardio.start,
            durationSec: cardio.duration,
            distanceM: cardio.distance,
            paceSecPerKm: pace,
            calories: cardio.activeEnergy,
            avgHR: cardio.avgHeartRate,
            maxHR: cardio.maxHeartRate,
            totalVolumeKg: nil,
            setCount: 0,
            exercises: [],
            hr: cardio.orderedHRSamples.map { (t: $0.t, bpm: $0.bpm) },
            route: cardio.orderedRouteSamples.map { (lat: $0.lat, lon: $0.lon) }
        )
    }
}
