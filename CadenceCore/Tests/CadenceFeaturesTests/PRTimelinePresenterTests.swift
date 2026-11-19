import Foundation
import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

struct PRTimelinePresenterTests {

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

    private func event(_ name: String = "Squat", kind: PRKind = .weight,
                       value: Double, previous: Double?, day n: Int = 1) -> PREvent {
        PREvent(exerciseName: name, date: day(n), kind: kind,
                value: value, reps: 5, weightKg: value, previous: previous)
    }

    @Test func firstEverHasNoDeltaAndFirstEverAccent() {
        let rows = PRTimelinePresenter.rows(events: [event(value: 100, previous: nil)],
                                            unit: .kilograms)
        #expect(rows.count == 1)
        #expect(rows[0].accent == .firstEver)
        #expect(rows[0].deltaLabel == nil)
        #expect(rows[0].valueLabel == "100 kg")
    }

    @Test func improvementHasDeltaLabelAndAccent() {
        let rows = PRTimelinePresenter.rows(events: [event(value: 105, previous: 100)],
                                            unit: .kilograms)
        #expect(rows[0].accent == .improvement)
        #expect(rows[0].deltaLabel == "+5 kg over your last best")
    }

    @Test func e1RMValueLabelSuffixed() {
        let rows = PRTimelinePresenter.rows(
            events: [event(kind: .e1RM, value: 128, previous: nil)], unit: .kilograms)
        #expect(rows[0].valueLabel == "128 kg e1RM")
    }

    @Test func volumeValueLabelUnitAware() {
        let rows = PRTimelinePresenter.rows(
            events: [event(kind: .volume, value: 640, previous: nil)], unit: .kilograms)
        #expect(rows[0].valueLabel == "640 kg\u{00b7}reps")
    }

    @Test func rowsAreNewestFirst() {
        let events = [
            event(value: 100, previous: nil, day: 1),
            event(value: 110, previous: 100, day: 3)
        ]
        let rows = PRTimelinePresenter.rows(events: events, unit: .kilograms)
        #expect(rows.first?.valueLabel == "110 kg")   // newest first
        #expect(rows.last?.valueLabel == "100 kg")
    }

    @Test func poundsConvertsValueAndDelta() {
        let rows = PRTimelinePresenter.rows(
            events: [event(value: 100, previous: 90)], unit: .pounds)
        // 100 kg → ~220 lb, delta 10 kg → ~22 lb
        #expect(rows[0].valueLabel.contains("lb"))
        #expect(rows[0].deltaLabel?.contains("lb") ?? false)
    }
}
