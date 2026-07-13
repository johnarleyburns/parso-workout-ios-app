import XCTest
import CadenceCore
import CadenceFeatures

@MainActor
final class OnboardingModelTests: XCTestCase {

    func testStartsAtFirstStep() {
        let m = OnboardingModel()
        XCTAssertEqual(m.step, 0)
        XCTAssertFalse(m.canGoBack)
        XCTAssertFalse(m.isLastStep)
        XCTAssertEqual(m.primaryAction, .advance)
    }

    func testAdvanceStopsAtLastStep() {
        let m = OnboardingModel()
        for _ in 0..<10 { m.advance() }
        XCTAssertEqual(m.step, m.lastStep)
        XCTAssertTrue(m.isLastStep)
        XCTAssertEqual(m.primaryAction, .complete)
    }

    func testBackStopsAtZero() {
        let m = OnboardingModel(step: 1)
        m.back()
        XCTAssertEqual(m.step, 0)
        m.back()
        XCTAssertEqual(m.step, 0)
    }

    func testFooterTitleByStep() {
        let m = OnboardingModel()
        XCTAssertEqual(m.footerTitle, "Continue")
        m.step = 5
        XCTAssertEqual(m.footerTitle, "I understand")
        m.step = m.lastStep
        XCTAssertEqual(m.footerTitle, "Start training with the Coach")
    }

    func testSchedulePreferencesReflectDayChoices() {
        let m = OnboardingModel(strengthDays: 4, cardioDays: 2)
        let prefs = m.schedulePreferences
        XCTAssertEqual(prefs.strengthDaysPerWeek, 4)
        XCTAssertEqual(prefs.cardioDaysPerWeek, 2)
        XCTAssertFalse(prefs.allowsTwoADays)
    }

    func testPersistedAgeOnlyWhenProvided() {
        let m = OnboardingModel(age: 33, ageProvided: false)
        XCTAssertNil(m.persistedAge)
        m.ageProvided = true
        XCTAssertEqual(m.persistedAge, 33)
    }

    func testPreviewPlanGenerates() {
        let m = OnboardingModel(goal: .strength, experience: .intermediate, strengthDays: 3, cardioDays: 2)
        let plan = m.previewPlan(formula: .epley)
        XCTAssertFalse(plan.days.isEmpty)
    }
}
