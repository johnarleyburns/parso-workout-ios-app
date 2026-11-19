import Foundation
import Testing
@testable import CadenceCore

struct WatchCardioCompletionTests {
    @Test func roundTripPreservesVersionedCompletion() throws {
        let id = UUID()
        let value = WatchCardioCompletion(id: id, type: .run, title: "Morning run",
                                          start: Date(timeIntervalSince1970: 100),
                                          end: Date(timeIntervalSince1970: 200),
                                          distanceMeters: 5000,
                                          hrSamples: [HRSamplePoint(t: 2, bpm: 140)],
                                          avgHeartRate: 135, maxHeartRate: 160,
                                          gpsEnabled: true)
        #expect(try WatchCardioCompletion.decode(value.encoded()) == value)
    }

    @Test func unsupportedVersionIsRejected() throws {
        let value = WatchCardioCompletion(type: .walk, start: Date(), end: Date(), version: 99)
        #expect(throws: WatchCardioCompletion.DecodeError.unsupportedVersion(99)) {
            try WatchCardioCompletion.decode(value.encoded())
        }
    }

    @Test func nonGPSDistanceIsRemovedFromEnvelope() {
        let value = WatchCardioCompletion(type: .cycle, start: Date(), end: Date(),
                                          distanceMeters: 1000, gpsEnabled: false)
        #expect(value.distanceMeters == nil)
    }
    @Test func poolSwimPreservesDistanceLapsAndPoolSizeWithoutGPS() throws {
        let value = WatchCardioCompletion(type: .swim, start: Date(), end: Date(),
            distanceMeters: 500, gpsEnabled: false, swimmingLapCount: 20, poolLengthMeters: 25)
        #expect(try WatchCardioCompletion.decode(value.encoded()) == value)
        #expect(value.distanceMeters == 500)
        #expect(value.ingestedWorkout.distanceMeters == 500)
        #expect(value.swimmingLapCount == 20)
        #expect(value.poolLengthMeters == 25)
        #expect(!value.gpsEnabled)
    }

    @Test func legacyCompletionStillDecodesWithoutSwimmingFields() throws {
        let value = WatchCardioCompletion(type: .swim, start: Date(), end: Date())
        var json = try #require(JSONSerialization.jsonObject(with: value.encoded()) as? [String: Any])
        json.removeValue(forKey: "swimmingLapCount")
        json.removeValue(forKey: "poolLengthMeters")
        let decoded = try WatchCardioCompletion.decode(JSONSerialization.data(withJSONObject: json))
        #expect(decoded.swimmingLapCount == nil)
        #expect(decoded.poolLengthMeters == nil)
    }

}
