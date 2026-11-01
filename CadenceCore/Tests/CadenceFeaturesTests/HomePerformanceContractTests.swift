import XCTest
import Foundation
@testable import CadenceFeatures

final class HomePerformanceContractTests: XCTestCase {
    func testCachedRestoreBeforeHeavyWorkIsValid() {
        let sink = RecordingHomePerformanceEventSink()
        for e: HomePerformanceEvent in [.firstTodayFrame, .heroRestored, .suggestionRestored, .thisWeekInteractive,
                                        .historyReadStarted, .coachIdentityEvaluated, .fullSnapshotStarted,
                                        .weeklyProjectionStarted, .weeklyProjectionPublished] {
            sink.record(e)
        }
        XCTAssertEqual(HomePerformanceContract.violations(in: sink.events), [])
        let times = sink.entries.map(\.uptimeNanoseconds)
        XCTAssertEqual(times, times.sorted(), "timestamps must be monotonic")
    }

    func testRestoreAfterHistoryReadIsRejected() {
        let events: [HomePerformanceEvent] = [.firstTodayFrame, .historyReadStarted, .heroRestored,
                                              .suggestionRestored, .thisWeekInteractive]
        XCTAssertFalse(HomePerformanceContract.violations(in: events).isEmpty)
    }

    func testMissingRestoreAndLateInteractivityAreRejected() {
        XCTAssertFalse(HomePerformanceContract.violations(in: [.firstTodayFrame]).isEmpty)
        let late: [HomePerformanceEvent] = [.heroRestored, .suggestionRestored, .weeklyProjectionStarted,
                                            .weeklyProjectionPublished, .thisWeekInteractive]
        XCTAssertFalse(HomePerformanceContract.violations(in: late).isEmpty)
    }

    func testEventNamesAreContentFree() {
        for e in HomePerformanceEvent.allCases {
            XCTAssertNil(e.rawValue.rangeOfCharacter(from: .decimalDigits))
        }
    }
}
