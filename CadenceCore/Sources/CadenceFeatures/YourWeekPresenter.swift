import Foundation
import CadenceCore

/// Coach-domain logic pulled out of `YourWeekView` (test-pyramid Phase 1): the
/// weekly HR-zone aggregation and the modality/intensity classification of cardio
/// workouts. Pure — the view keeps only the `Color` mapping of a zone.
public enum YourWeekPresenter {

    /// One zone's weekly minute total, for the zone legend rows.
    public struct ZoneRow: Equatable {
        public let zone: Int
        public let minutes: Double
        public init(zone: Int, minutes: Double) {
            self.zone = zone
            self.minutes = minutes
        }
    }

    /// Weekly minutes in each HR zone (1…5) for cardio started on/after `since`.
    /// Uses recorded HR samples when present, else classifies from modality +
    /// intensity against an age-based HRmax.
    public static func weeklyZoneMinutes(cardio: [CardioWorkout],
                                         since: Date,
                                         age: Int?) -> [Int: Double] {
        let weekCardio = cardio.filter { $0.start >= since }
        let sessionsForZones: [CardioZoneAggregator.Session] = weekCardio.map { c in
            CardioZoneAggregator.Session(
                modality: modality(for: c.typeValue),
                intensity: intensity(for: c, age: age),
                durationMinutes: c.duration / 60,
                hrSamples: (c.hrSamples ?? []).map { CardioZoneAggregator.HRPoint(t: $0.t, bpm: $0.bpm) })
        }
        return CardioZoneAggregator.weeklyZoneMinutes(sessions: sessionsForZones, age: age)
    }

    /// The non-empty zone rows (minutes > 0.5), ascending Z1…Z5.
    public static func zoneRows(_ minutes: [Int: Double]) -> [ZoneRow] {
        (1...5).compactMap { z in
            guard let m = minutes[z], m > 0.5 else { return nil }
            return ZoneRow(zone: z, minutes: m)
        }
    }

    public static func modality(for type: CardioType) -> CoachSession.AerobicModality {
        switch type {
        case .walk: return .walk
        case .run: return .run
        case .cycle: return .cycle
        case .swim: return .swim
        case .rowing: return .row
        case .boxing: return .boxing
        default: return .other
        }
    }

    /// Rough intensity from average HR against an age-based HRmax when present;
    /// else inferred from modality (boxing/run lean harder than walk).
    public static func intensity(for c: CardioWorkout, age: Int?) -> CoachSession.AerobicIntensity {
        if let avg = c.avgHeartRate, avg > 0 {
            let maxHR = CardioMath.defaultMaxHR(age: age)
            let pct = avg / maxHR
            if pct >= 0.80 { return .vigorous }
            if pct >= 0.65 { return .moderate }
            return .easy
        }
        switch c.typeValue {
        case .boxing: return .vigorous
        case .run, .rowing: return .moderate
        default: return .easy
        }
    }
}
