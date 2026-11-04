import XCTest
@testable import CadenceFeatures
import CadenceCore

final class WatchCardioIntensityProfileSyncTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    func testRoundTripPreservesProfile() throws {
        let profile = CardioIntensityProfile(restingHR: 63, maximumHR: 173,
                                             maximumHRSource: .userEntered, vo2Max: 42.5,
                                             updatedAt: stamp)
        let prefs = WatchSync.Preferences(cardioIntensityProfile: profile)
        let ctx = WatchSync.Preferences.contextDict(prefs, updatedAt: stamp)
        XCTAssertTrue(ctx[WatchSync.Key.cardioIntensityProfile] is Data)
        let incoming = WatchSync.IncomingContext.from(context: ctx, applyingTo: WatchSync.Preferences())
        XCTAssertEqual(incoming.preferences.cardioIntensityProfile, profile)
    }

    func testOldContextYieldsNilProfile() {
        let ctx = WatchSync.Preferences.contextDict(WatchSync.Preferences(), updatedAt: stamp)
        let incoming = WatchSync.IncomingContext.from(context: ctx, applyingTo: WatchSync.Preferences())
        XCTAssertNil(incoming.preferences.cardioIntensityProfile)
    }

    func testMalformedDataKeepsPreviousValidProfile() {
        let good = CardioIntensityProfile(restingHR: 60, maximumHR: 180, maximumHRSource: .agePredicted)
        let base = WatchSync.Preferences(cardioIntensityProfile: good)
        var ctx = WatchSync.Preferences.contextDict(WatchSync.Preferences(), updatedAt: stamp)
        ctx[WatchSync.Key.cardioIntensityProfile] = Data("not json".utf8)
        XCTAssertEqual(base.applying(context: ctx).cardioIntensityProfile, good)
        let fresh = WatchSync.IncomingContext.from(context: ctx, applyingTo: WatchSync.Preferences())
        XCTAssertNil(fresh.preferences.cardioIntensityProfile)
    }

    func testProviderMedianOfNewestSevenValidSamples() {
        let day: TimeInterval = 86_400
        // Newest seven valid (oldest-first below): 70, 55, 63, 66, 60, 64, 62 -> sorted median 63.
        let valid: [(Int, Double)] = [(1, 70), (2, 55), (3, 63), (4, 66), (5, 60), (6, 64), (7, 62)]
        var samples = valid.map { PassiveReadinessSample(date: stamp.addingTimeInterval(-Double($0.0) * day), restingHR: $0.1) }
        samples.append(PassiveReadinessSample(date: stamp.addingTimeInterval(-0.5 * day), restingHR: 10))   // invalid
        samples.append(PassiveReadinessSample(date: stamp.addingTimeInterval(-0.6 * day), restingHR: 250))  // invalid
        samples.append(PassiveReadinessSample(date: stamp.addingTimeInterval(-30 * day), restingHR: 90))    // too old
        samples.shuffle()
        XCTAssertEqual(CardioIntensityProfileProvider.restingHR(from: samples), 63)
    }

    func testWatchProfileClassifiesLikePhone() {
        let phone = CardioIntensityProfileProvider.profile(
            samples: [PassiveReadinessSample(date: stamp, restingHR: 63)], vo2Max: nil,
            maximumHROverride: nil, age: 50)
        XCTAssertEqual(phone.maximumHR ?? 0, 173, accuracy: 0.001)
        let watch = CardioIntensityProfileProvider.decode(CardioIntensityProfileProvider.encode(phone)!)!
        for hr in stride(from: 80.0, through: 180.0, by: 10) {
            XCTAssertEqual(CardioIntensityClassifier.classify(heartRate: hr, profile: watch),
                           CardioIntensityClassifier.classify(heartRate: hr, profile: phone))
        }
    }
}
