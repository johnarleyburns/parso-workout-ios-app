import XCTest
import CadenceFeatures

final class SetRowAccessibilityTests: XCTestCase {
    func testCompletedOwnerSetDescribesValueAndActions() {
        let descriptor = SetRowAccessibility.completed(
            exercise: "Bench Press", setNumber: "3", weight: "100 kg", reps: 5,
            rpe: 8, performer: nil, isWarmup: false)

        XCTAssertEqual(descriptor.label, "set 3, Bench Press, 100 kg × 5, logged, RPE 8")
        XCTAssertEqual(descriptor.actions, [.edit, .repeatSet, .delete])
    }

    func testCompletedPartnerSetNamesThePerformer() {
        let descriptor = SetRowAccessibility.completed(
            exercise: "Row", setNumber: "2", weight: "57 kg", reps: 8,
            rpe: nil, performer: "Audrey", isWarmup: false)

        XCTAssertTrue(descriptor.label.contains("Audrey"))
        XCTAssertTrue(descriptor.label.contains("57 kg"))
    }

    func testCurrentPendingSetOffersLogAndEdit() {
        let descriptor = SetRowAccessibility.pending(
            exercise: "Bench Press", setNumber: 3, planned: 5, reps: 5,
            weight: "100 kg", performer: "Me", isCurrent: true)

        XCTAssertEqual(descriptor.label, "Set 3 of 5, Bench Press, Me, 100 kg, 5 reps, next set, not logged")
        XCTAssertEqual(descriptor.actions, [.log, .edit])
    }

    func testLaterPendingSetDoesNotOfferLog() {
        let descriptor = SetRowAccessibility.pending(
            exercise: "Squat", setNumber: 4, planned: 4, reps: 8,
            weight: nil, performer: nil, isCurrent: false)

        XCTAssertEqual(descriptor.actions, [.edit])
        XCTAssertTrue(descriptor.label.contains("not logged"))
    }
}
