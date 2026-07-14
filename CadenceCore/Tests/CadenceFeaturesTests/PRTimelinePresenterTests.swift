import XCTest
@testable import CadenceFeatures
import CadenceCore

final class PRTimelinePresenterTests: XCTestCase {

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

    private func event(_ name: String = "Squat", kind: PRKind = .weight,
                       value: Double, previous: Double?, day n: Int = 1) -> PREvent {
        PREvent(exerciseName: name, date: day(n), kind: kind,
                value: value, reps: 5, weightKg: value, previous: previous)
    }

    func testFirstEverHasNoDeltaAndFirstEverAccent() {
        let rows = PRTimelinePresenter.rows(events: [event(value: 100, previous: nil)],
                                            unit: .kilograms)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].accent, .firstEver)
        XCTAssertNil(rows[0].deltaLabel)
        XCTAssertEqual(rows[0].valueLabel, "100 kg")
    }

    func testImprovementHasDeltaLabelAndAccent() {
        let rows = PRTimelinePresenter.rows(events: [event(value: 105, previous: 100)],
                                            unit: .kilograms)
        XCTAssertEqual(rows[0].accent, .improvement)
        XCTAssertEqual(rows[0].deltaLabel, "+5 kg over your last best")
    }

    func testE1RMValueLabelSuffixed() {
        let rows = PRTimelinePresenter.rows(
            events: [event(kind: .e1RM, value: 128, previous: nil)], unit: .kilograms)
        XCTAssertEqual(rows[0].valueLabel, "128 kg e1RM")
    }

    func testVolumeValueLabelUnitAware() {
        let rows = PRTimelinePresenter.rows(
            events: [event(kind: .volume, value: 640, previous: nil)], unit: .kilograms)
        XCTAssertEqual(rows[0].valueLabel, "640 kg\u{00b7}reps")
    }

    func testRowsAreNewestFirst() {
        let events = [
            event(value: 100, previous: nil, day: 1),
            event(value: 110, previous: 100, day: 3)
        ]
        let rows = PRTimelinePresenter.rows(events: events, unit: .kilograms)
        XCTAssertEqual(rows.first?.valueLabel, "110 kg")   // newest first
        XCTAssertEqual(rows.last?.valueLabel, "100 kg")
    }

    func testPoundsConvertsValueAndDelta() {
        let rows = PRTimelinePresenter.rows(
            events: [event(value: 100, previous: 90)], unit: .pounds)
        // 100 kg → ~220 lb, delta 10 kg → ~22 lb
        XCTAssertTrue(rows[0].valueLabel.contains("lb"))
        XCTAssertTrue(rows[0].deltaLabel?.contains("lb") ?? false)
    }
}
