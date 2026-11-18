import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct TodayRequestCardPresenterTests {
    @Test func idleStateShowsRequestButtonTappable() {
        let d = TodayRequestCardPresenter.make(title: "Suggest a strength workout", state: .idle, resultSummary: nil)
        #expect(!d.isLoading)
        #expect(d.isTappable)
        #expect(d.buttonLabel == "Suggest a strength workout")
        #expect(d.accessibilityLabel == "Suggest a strength workout")
    }

    @Test func requestingStateIsLoadingAndNotTappable() {
        let d = TodayRequestCardPresenter.make(title: "Suggest a strength workout", state: .requesting, resultSummary: nil)
        #expect(d.isLoading)
        #expect(!d.isTappable)
        #expect(d.accessibilityLabel.contains("Suggest a strength workout"))
    }

    @Test func resultStateShowsSummaryAndIsTappableToReopen() {
        let d = TodayRequestCardPresenter.make(title: "Suggest a strength workout", state: .result,
                                               resultSummary: "Upper Body Hypertrophy · 45 min")
        #expect(d.title == "Upper Body Hypertrophy · 45 min")
        #expect(d.isTappable)
        #expect(!d.isLoading)
    }

    @Test func resultStateFallsBackToOriginalTitleIfSummaryMissing() {
        let d = TodayRequestCardPresenter.make(title: "Suggest cardio", state: .result, resultSummary: nil)
        #expect(d.title == "Suggest cardio")
    }

    @Test func failedStateShowsTryAgainAndSurfacesMessageInAccessibilityLabel() {
        let d = TodayRequestCardPresenter.make(title: "Suggest cardio", state: .failed("No history yet"),
                                               resultSummary: nil)
        #expect(d.buttonLabel == "Try again")
        #expect(d.isTappable)
        #expect(d.accessibilityLabel.contains("No history yet"))
    }
}
