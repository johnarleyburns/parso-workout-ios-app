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
        /// Heaviest working-set weight (kg) for this exercise, if any. For a
        /// bodyweight exercise this is the heaviest *added* load (0 = pure BW).
        public let topSetWeightKg: Double?
        /// Reps of each working set, in logged order.
        public let reps: [Int]
        /// True when this exercise's working sets are bodyweight (feedback batch
        /// 3) — the view renders "BW" / "BW + X" rather than a bare weight.
        public let usesBodyweight: Bool

        public init(name: String, setCount: Int, topSetWeightKg: Double?, reps: [Int],
                    usesBodyweight: Bool = false) {
            self.name = name
            self.setCount = setCount
            self.topSetWeightKg = topSetWeightKg
            self.reps = reps
            self.usesBodyweight = usesBodyweight
        }
    }

    /// A training partner's roll-up within a strength summary (feedback batch 3):
    /// their working sets, so partnered history shows what the partner did too.
    public struct PartnerSummary: Equatable, Sendable, Identifiable {
        public let name: String
        public let exercises: [ExerciseLine]
        public var id: String { name }

        public init(name: String, exercises: [ExerciseLine]) {
            self.name = name
            self.exercises = exercises
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
    public let laps: Int?                     // swimming (round4b feedback #3)
    public let targetLaps: Int?
    public let totalVolumeKg: Double?        // strength
    public let setCount: Int                 // strength: owner working-set count
    public let totalReps: Int                // strength: owner working-set reps, summed
    public let exercises: [ExerciseLine]     // strength: owner's working sets
    public let partners: [PartnerSummary]    // strength: each partner's working sets
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
                laps: Int? = nil,
                targetLaps: Int? = nil,
                totalVolumeKg: Double? = nil,
                setCount: Int = 0,
                totalReps: Int = 0,
                exercises: [ExerciseLine] = [],
                partners: [PartnerSummary] = [],
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
        self.laps = laps
        self.targetLaps = targetLaps
        self.totalVolumeKg = totalVolumeKg
        self.setCount = setCount
        self.totalReps = totalReps
        self.exercises = exercises
        self.partners = partners
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
            && lhs.laps == rhs.laps
            && lhs.targetLaps == rhs.targetLaps
            && lhs.totalVolumeKg == rhs.totalVolumeKg
            && lhs.setCount == rhs.setCount
            && lhs.totalReps == rhs.totalReps
            && lhs.exercises == rhs.exercises
            && lhs.partners == rhs.partners
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
        // List every exercise the owner actually performed, in order. Previously
        // an exercise whose only sets were warmups was silently dropped, so a
        // logged movement could vanish from history (round4b feedback #7). Now we
        // keep any exercise with ≥1 owner set; the line still summarizes only the
        // owner's working (non-warmup) sets. Partner-only exercises are excluded.
        // Owner lines: every exercise with ≥1 owner set (warmup-only lines keep a
        // setCount of 0 rather than vanishing — round4b feedback #7).
        let exercises = lines(in: session) { $0.isOwnerSet }
        let setCount = exercises.reduce(0) { $0 + $1.setCount }
        let totalReps = exercises.reduce(0) { $0 + $1.reps.reduce(0, +) }
        // Partner lines: grouped by partner name, in first-appearance order
        // (feedback batch 3 — partnered history shows what the partner did too).
        var partnerOrder: [String] = []
        for set in session.orderedSets {
            guard let p = set.performedBy, !p.isMe else { continue }
            if !partnerOrder.contains(p.name) { partnerOrder.append(p.name) }
        }
        let partners: [PartnerSummary] = partnerOrder.map { name in
            PartnerSummary(name: name,
                           exercises: lines(in: session) { $0.performedBy?.name == name && !($0.performedBy?.isMe ?? true) })
        }
        return WorkoutSummaryData(
            kind: .strength,
            title: session.title,
            date: session.date,
            durationSec: session.duration,
            totalVolumeKg: session.totalVolume,
            setCount: setCount,
            totalReps: totalReps,
            exercises: exercises,
            partners: partners
        )
    }

    /// Builds per-exercise lines for the sets matching `belongs`, keeping any
    /// exercise with ≥1 matching set (working sets summarize the line).
    private static func lines(in session: WorkoutSession,
                             belongs: (SetEntry) -> Bool) -> [ExerciseLine] {
        session.exercisesInOrder.compactMap { ex in
            let mine = session.orderedSets.filter { $0.exercise?.id == ex.id && belongs($0) }
            guard !mine.isEmpty else { return nil }
            let working = mine.filter { !$0.isWarmup }
            return ExerciseLine(name: ex.name,
                                setCount: working.count,
                                topSetWeightKg: working.map(\.weight).max(),
                                reps: working.map(\.reps),
                                usesBodyweight: working.contains { $0.usesBodyweight })
        }
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
            laps: cardio.laps,
            targetLaps: cardio.targetLaps,
            totalVolumeKg: nil,
            setCount: 0,
            exercises: [],
            hr: cardio.orderedHRSamples.map { (t: $0.t, bpm: $0.bpm) },
            route: cardio.orderedRouteSamples.map { (lat: $0.lat, lon: $0.lon) }
        )
    }
}
