import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchHRLiveStatusTests {
    @Test func roundTripAndNoBPM() {
        let id = UUID(); let end = Date(timeIntervalSince1970: 1234)
        let s = WatchHRLiveStatus(requestID: id, lastRealSampleEnd: end, sensorHasFreshReading: false)
        #expect(s.payload["bpm"] == nil)
        #expect(WatchHRLiveStatus(payload: s.payload) == s)
    }
    @Test func malformedRejected() {
        #expect(WatchHRLiveStatus(payload: ["requestID": UUID().uuidString]) == nil)
        #expect(WatchHRLiveStatus(payload: [WatchHRLiveStatus.key: true, "requestID": "nope"]) == nil)
    }
}
