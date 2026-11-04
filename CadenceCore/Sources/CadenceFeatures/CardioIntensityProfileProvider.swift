import Foundation
import CadenceCore

/// Shared construction policy for the HRR-aware `CardioIntensityProfile` used by the phone and
/// delivered to the Watch. Recent resting HR is the median of the newest seven valid passive
/// samples (`30 < bpm < 220`); max HR follows `CardioIntensityProfile.resolved` precedence.
public enum CardioIntensityProfileProvider {
    public static func restingHR(from samples: [PassiveReadinessSample]) -> Double? {
        let values = samples
            .sorted { $0.date > $1.date }
            .compactMap(\.restingHR)
            .filter { $0.isFinite && $0 > 30 && $0 < 220 }
            .prefix(7)
            .sorted()
        if values.isEmpty { return nil }
        if values.count % 2 == 1 { return values[values.count / 2] }
        return (values[values.count / 2 - 1] + values[values.count / 2]) / 2
    }

    public static func profile(samples: [PassiveReadinessSample], vo2Max: Double?,
                               maximumHROverride: Double?, age: Int?,
                               updatedAt: Date? = nil) -> CardioIntensityProfile {
        CardioIntensityProfile.resolved(
            restingHR: restingHR(from: samples),
            userEnteredMaximumHR: maximumHROverride,
            age: age, vo2Max: vo2Max, updatedAt: updatedAt)
    }

    /// True when the profile can drive classification (a finite maximum above any resting HR).
    public static func isValid(_ profile: CardioIntensityProfile) -> Bool {
        guard let maximum = profile.maximumHR, maximum.isFinite, maximum > 0 else { return false }
        if let resting = profile.restingHR, !(resting.isFinite && resting > 0 && resting < maximum) {
            return false
        }
        return true
    }

    public static func encode(_ profile: CardioIntensityProfile) -> Data? {
        try? JSONEncoder().encode(profile)
    }

    /// nil for malformed data; never fabricates a profile.
    public static func decode(_ data: Data) -> CardioIntensityProfile? {
        guard let profile = try? JSONDecoder().decode(CardioIntensityProfile.self, from: data),
              isValid(profile) else { return nil }
        return profile
    }

    /// Equality ignoring the timestamp, so an unchanged profile does not churn the sync revision.
    public static func sameContent(_ a: CardioIntensityProfile?, _ b: CardioIntensityProfile?) -> Bool {
        var x = a, y = b
        x?.updatedAt = nil
        y?.updatedAt = nil
        return x == y
    }
}
