import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchWeekRingsTests: XCTestCase {
    func testToneBands() {
        func tone(_ v: Double) -> WatchWeekRingTone {
            WatchWeekRing(kind: .strength, value: v, minimum: 20, target: 60).tone
        }
        XCTAssertEqual(tone(0), .red)
        XCTAssertEqual(tone(1), .yellow)
        XCTAssertEqual(tone(19.9), .yellow)
        XCTAssertEqual(tone(20), .lightBlue)
        XCTAssertEqual(tone(59), .lightBlue)
        XCTAssertEqual(tone(60), .green)
        XCTAssertEqual(tone(90), .green)
    }

    func testProgressClampsAndHandlesZeroTarget() {
        XCTAssertEqual(WatchWeekRing(kind: .cardio, value: 450, minimum: 150, target: 300).progress, 1)
        XCTAssertEqual(WatchWeekRing(kind: .cardio, value: 150, minimum: 150, target: 300).progress, 0.5)
        XCTAssertEqual(WatchWeekRing(kind: .cardio, value: 10, minimum: 0, target: 0).progress, 0)
    }

    func testRingsOrderAndDefaults() {
        let empty = WatchWeekRings.rings(from: nil)
        XCTAssertEqual(empty.map(\.kind), [.strength, .cardio])
        XCTAssertEqual(empty.map(\.tone), [.red, .red])
        XCTAssertEqual(empty[1].minimum, 150)
        XCTAssertEqual(empty[1].target, 300)

        let summary = WatchSync.WeekSummary(sets: 30, setsMinimum: 40, setsTarget: 120,
                                            cardioMinutes: 200, updatedAt: Date())
        let rings = WatchWeekRings.rings(from: summary)
        XCTAssertEqual(rings[0].tone, .yellow)
        XCTAssertEqual(rings[1].tone, .lightBlue)
        XCTAssertEqual(rings[1].displayValue, 200)
    }

    func testWeekSummaryContextRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_000)
        let summary = WatchSync.WeekSummary(sets: 12.5, setsMinimum: 40, setsTarget: 120,
                                            cardioMinutes: 95, updatedAt: date)
        let context = WatchSync.WeekSummary.contextDict(summary)
        XCTAssertEqual(WatchSync.WeekSummary.from(context: context), summary)
        XCTAssertNil(WatchSync.WeekSummary.from(context: [:]))
        let incoming = WatchSync.IncomingContext.from(
            context: context, applyingTo: WatchSync.Preferences())
        XCTAssertEqual(incoming.weekSummary, summary)
    }
}
