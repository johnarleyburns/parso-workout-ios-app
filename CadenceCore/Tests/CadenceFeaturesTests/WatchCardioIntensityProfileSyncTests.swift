import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

struct WatchCardioIntensityProfileSyncTests {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func roundTripPreservesProfile() throws {
        let profile = CardioIntensityProfile(restingHR: 63, maximumHR: 173,
                                             maximumHRSource: .userEntered, vo2Max: 42.5,
                                             updatedAt: stamp)
        let prefs = WatchSync.Preferences(cardioIntensityProfile: profile)
        let ctx = WatchSync.Preferences.contextDict(prefs, updatedAt: stamp)
        #expect(ctx[WatchSync.Key.cardioIntensityProfile] is Data)
        let incoming = WatchSync.IncomingContext.from(context: ctx, applyingTo: WatchSync.Preferences())
        #expect(incoming.preferences.cardioIntensityProfile == profile)
    }

    @Test func oldContextYieldsNilProfile() {
        let ctx = WatchSync.Preferences.contextDict(WatchSync.Preferences(), updatedAt: stamp)
        let incoming = WatchSync.IncomingContext.from(context: ctx, applyingTo: WatchSync.Preferences())
        #expect(incoming.preferences.cardioIntensityProfile == nil)
    }

    @Test func malformedDataKeepsPreviousValidProfile() {
        let good = CardioIntensityProfile(restingHR: 60, maximumHR: 180, maximumHRSource: .agePredicted)
        let base = WatchSync.Preferences(cardioIntensityProfile: good)
        var ctx = WatchSync.Preferences.contextDict(WatchSync.Preferences(), updatedAt: stamp)
        ctx[WatchSync.Key.cardioIntensityProfile] = Data("not json".utf8)
        #expect(base.applying(context: ctx).cardioIntensityProfile == good)
        let fresh = WatchSync.IncomingContext.from(context: ctx, applyingTo: WatchSync.Preferences())
        #expect(fresh.preferences.cardioIntensityProfile == nil)
    }

    @Test func providerMedianOfNewestSevenValidSamples() {
        let day: TimeInterval = 86_400
        // Newest seven valid (oldest-first below): 70, 55, 63, 66, 60, 64, 62 -> sorted median 63.
        let valid: [(Int, Double)] = [(1, 70), (2, 55), (3, 63), (4, 66), (5, 60), (6, 64), (7, 62)]
        var samples = valid.map { PassiveReadinessSample(date: stamp.addingTimeInterval(-Double($0.0) * day), restingHR: $0.1) }
        samples.append(PassiveReadinessSample(date: stamp.addingTimeInterval(-0.5 * day), restingHR: 10))   // invalid
        samples.append(PassiveReadinessSample(date: stamp.addingTimeInterval(-0.6 * day), restingHR: 250))  // invalid
        samples.append(PassiveReadinessSample(date: stamp.addingTimeInterval(-30 * day), restingHR: 90))    // too old
        samples.shuffle()
        #expect(CardioIntensityProfileProvider.restingHR(from: samples) == 63)
    }

    @Test func watchProfileClassifiesLikePhone() {
        let phone = CardioIntensityProfileProvider.profile(
            samples: [PassiveReadinessSample(date: stamp, restingHR: 63)], vo2Max: nil,
            maximumHROverride: nil, age: 50)
        #expect(abs((phone.maximumHR ?? 0) - 173) <= 0.001)
        let watch = CardioIntensityProfileProvider.decode(CardioIntensityProfileProvider.encode(phone)!)!
        for hr in stride(from: 80.0, through: 180.0, by: 10) {
            #expect(CardioIntensityClassifier.classify(heartRate: hr, profile: watch) ==
                           CardioIntensityClassifier.classify(heartRate: hr, profile: phone))
        }
    }
}
