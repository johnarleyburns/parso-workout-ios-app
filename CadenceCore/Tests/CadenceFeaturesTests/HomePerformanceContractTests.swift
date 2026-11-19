import Testing
import Foundation
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct HomePerformanceContractTests {
    @Test func cachedRestoreBeforeHeavyWorkIsValid() {
        let sink = RecordingHomePerformanceEventSink()
        for e: HomePerformanceEvent in [.firstTodayFrame, .heroRestored, .suggestionRestored, .thisWeekInteractive,
                                        .historyReadStarted, .coachIdentityEvaluated, .fullSnapshotStarted,
                                        .weeklyProjectionStarted, .weeklyProjectionPublished] {
            sink.record(e)
        }
        #expect(HomePerformanceContract.violations(in: sink.events) == [])
        let times = sink.entries.map(\.uptimeNanoseconds)
        #expect(times == times.sorted(), "timestamps must be monotonic")
    }

    @Test func restoreAfterHistoryReadIsRejected() {
        let events: [HomePerformanceEvent] = [.firstTodayFrame, .historyReadStarted, .heroRestored,
                                              .suggestionRestored, .thisWeekInteractive]
        #expect(!HomePerformanceContract.violations(in: events).isEmpty)
    }

    @Test func missingRestoreAndLateInteractivityAreRejected() {
        #expect(!HomePerformanceContract.violations(in: [.firstTodayFrame]).isEmpty)
        let late: [HomePerformanceEvent] = [.heroRestored, .suggestionRestored, .weeklyProjectionStarted,
                                            .weeklyProjectionPublished, .thisWeekInteractive]
        #expect(!HomePerformanceContract.violations(in: late).isEmpty)
    }

    @Test func eventNamesAreContentFree() {
        for e in HomePerformanceEvent.allCases {
            #expect(e.rawValue.rangeOfCharacter(from: .decimalDigits) == nil)
        }
    }
}
