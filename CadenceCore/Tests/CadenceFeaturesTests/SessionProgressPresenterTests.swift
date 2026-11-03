import Testing
@testable import CadenceFeatures

@Suite struct SessionProgressPresenterTests {
    @Test func spokenLabelAndCountsAreUnchanged() {
        for (c, p) in [(1, 1), (24, 24), (100, 100)] {
            let progress = SessionProgressPresenter.progress(completedWorkingSets: c, plannedWorkingSets: p)
            #expect(progress.completed == c)
            #expect(progress.planned == p)
            #expect(progress.label == "\(c) of \(p) sets")
        }
    }
}
