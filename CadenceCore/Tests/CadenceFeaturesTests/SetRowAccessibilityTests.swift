import Testing
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct SetRowAccessibilityTests {
    @Test func completedOwnerSetDescribesValueAndActions() {
        let descriptor = SetRowAccessibility.completed(
            exercise: "Bench Press", setNumber: "3", weight: "100 kg", reps: 5,
            rpe: 8, performer: nil, isWarmup: false)

        #expect(descriptor.label == "set 3, Bench Press, 100 kg × 5, logged, RPE 8")
        #expect(descriptor.actions == [.edit, .repeatSet, .delete])
    }

    @Test func completedPartnerSetNamesThePerformer() {
        let descriptor = SetRowAccessibility.completed(
            exercise: "Row", setNumber: "2", weight: "57 kg", reps: 8,
            rpe: nil, performer: "Audrey", isWarmup: false)

        #expect(descriptor.label.contains("Audrey"))
        #expect(descriptor.label.contains("57 kg"))
    }

    @Test func currentPendingSetOffersLogAndEdit() {
        let descriptor = SetRowAccessibility.pending(
            exercise: "Bench Press", setNumber: 3, planned: 5, reps: 5,
            weight: "100 kg", performer: "Me", isCurrent: true)

        #expect(descriptor.label == "Set 3 of 5, Bench Press, Me, 100 kg, 5 reps, next set, not logged")
        #expect(descriptor.actions == [.log, .edit])
    }

    @Test func laterPendingSetDoesNotOfferLog() {
        let descriptor = SetRowAccessibility.pending(
            exercise: "Squat", setNumber: 4, planned: 4, reps: 8,
            weight: nil, performer: nil, isCurrent: false)

        #expect(descriptor.actions == [.edit])
        #expect(descriptor.label.contains("not logged"))
    }
}
