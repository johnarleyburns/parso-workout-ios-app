import Testing
@testable import CadenceCore

/// P7 (issue 7) — weekly HR-zone aggregation, tonnage formatting, and the
/// completed strength+cardio day label fix.
struct CardioZoneAggregatorTests {

    @Test func estimatedZoneFromModalityWhenNoHR() {
        // Easy walk → Z1; easy run → Z2; moderate → Z3; vigorous → Z4.
        let walk = CardioZoneAggregator.Session(modality: .walk, intensity: .easy, durationMinutes: 30)
        let run = CardioZoneAggregator.Session(modality: .run, intensity: .easy, durationMinutes: 30)
        let mod = CardioZoneAggregator.Session(modality: .cycle, intensity: .moderate, durationMinutes: 40)
        let hard = CardioZoneAggregator.Session(modality: .run, intensity: .vigorous, durationMinutes: 20)
        let z = CardioZoneAggregator.weeklyZoneMinutes(sessions: [walk, run, mod, hard], age: 40)
        #expect(abs((z[1] ?? 0) - 30) <= 0.001)
        #expect(abs((z[2] ?? 0) - 30) <= 0.001)
        #expect(abs((z[3] ?? 0) - 40) <= 0.001)
        #expect(abs((z[4] ?? 0) - 20) <= 0.001)
    }

    @Test func zoneMinutesFromHRSamples() {
        // A 10-min session; first 5 min at 120 bpm, last 5 at 170 bpm. Age 30 →
        // HRmax ≈ 187. 120/187 ≈ 64% → Z2; 170/187 ≈ 91% → Z5.
        let samples = [
            CardioZoneAggregator.HRPoint(t: 0, bpm: 120),
            CardioZoneAggregator.HRPoint(t: 300, bpm: 170),
        ]
        let session = CardioZoneAggregator.Session(modality: .run, intensity: .moderate,
                                                   durationMinutes: 10, hrSamples: samples)
        let z = CardioZoneAggregator.weeklyZoneMinutes(sessions: [session], age: 30)
        #expect(abs((z[2] ?? 0) - 5) <= 0.001)
        #expect(abs((z[5] ?? 0) - 5) <= 0.001)
    }

    @Test func intensityProfileWeightsRepeatedHighBoutsWithoutPromotingWholeSession() {
        // Age 50 → HRmax 173. 136 bpm is Z3; 161 bpm is Z5. Two one-minute
        // high bouts are separated by recovery, so this is interval-like but
        // still mostly moderate work.
        let samples = [
            CardioZoneAggregator.HRPoint(t: 0, bpm: 136),
            CardioZoneAggregator.HRPoint(t: 120, bpm: 161),
            CardioZoneAggregator.HRPoint(t: 180, bpm: 136),
            CardioZoneAggregator.HRPoint(t: 300, bpm: 161),
            CardioZoneAggregator.HRPoint(t: 360, bpm: 136)
        ]
        let session = CardioZoneAggregator.Session(modality: .other, intensity: .moderate,
                                                     durationMinutes: 20, hrSamples: samples)
        let profile = CardioZoneAggregator.intensityProfile(for: session, maxHR: 173)
        #expect(abs(profile.moderateMinutes - 18) <= 0.001)
        #expect(abs(profile.vigorousMinutes - 2) <= 0.001)
        #expect(abs(profile.moderateEquivalentMinutes - 22) <= 0.001)
        #expect(profile.isIntervalLike)
        #expect(profile.dominantIntensity == .vigorous,
                       "interval intent is retained without treating all 20 minutes as vigorous")
    }

    @Test func oneShortHighPeakDoesNotTriggerIntervalDetection() {
        let samples = [
            CardioZoneAggregator.HRPoint(t: 0, bpm: 136),
            CardioZoneAggregator.HRPoint(t: 120, bpm: 161),
            CardioZoneAggregator.HRPoint(t: 130, bpm: 136)
        ]
        let session = CardioZoneAggregator.Session(modality: .other, intensity: .moderate,
                                                     durationMinutes: 20, hrSamples: samples)
        let profile = CardioZoneAggregator.intensityProfile(for: session, maxHR: 173)
        #expect(!profile.isIntervalLike)
        #expect(profile.dominantIntensity == .moderate)
    }

    @Test func emptyAndZeroDurationIgnored() {
        let empty = CardioZoneAggregator.Session(modality: .run, intensity: .easy, durationMinutes: 0)
        #expect(CardioZoneAggregator.weeklyZoneMinutes(sessions: [empty], age: 40).isEmpty)
        #expect(CardioZoneAggregator.weeklyZoneMinutes(sessions: [], age: nil).isEmpty)
    }

    // MARK: tonnage

    @Test func tonnageKgAndPounds() {
        // 12,400 kg = 12.4 t; in pounds = 27,337 lb ≈ 13.7 tn.
        #expect(WorkoutMath.tonnageLabel(volumeKg: 12_400, unit: .kilograms) == "12.4 t")
        let lbLabel = WorkoutMath.tonnageLabel(volumeKg: 12_400, unit: .pounds)
        #expect(lbLabel.hasSuffix(" tn"), "US tons suffix, got \(lbLabel)")
    }

    @Test func tonnageWholeNumberTrims() {
        #expect(WorkoutMath.tonnageLabel(volumeKg: 10_000, unit: .kilograms) == "10 t")
    }

    // MARK: HRmax public + Tanaka

    @Test func defaultMaxHRPublicTanaka() {
        #expect(abs(CardioMath.defaultMaxHR(age: 30) - (208 - 0.7 * 30)) <= 0.001)
        #expect(abs(CardioMath.defaultMaxHR(age: nil) - 190) <= 0.001)
    }
}
