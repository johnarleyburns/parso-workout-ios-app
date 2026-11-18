import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchExerciseFilterTests {

    @Test func filterNarrowsByMechanicsAndEquipment() {
        let entries = [
            ExerciseCatalogEntry(id: UUID(), name: "Squat", equipmentValue: .barbell, mechanicsValue: .compound),
            ExerciseCatalogEntry(id: UUID(), name: "Leg Extension", equipmentValue: .machine, mechanicsValue: .isolation),
            ExerciseCatalogEntry(id: UUID(), name: "Goblet Squat", equipmentValue: .dumbbell, mechanicsValue: .compound),
        ]
        #expect(WatchExerciseFilter().apply(to: entries).count == 3)
        #expect(!WatchExerciseFilter().isActive)
        let compound = WatchExerciseFilter(mechanics: .compound)
        #expect(compound.apply(to: entries).map(\.name) == ["Squat", "Goblet Squat"])
        #expect(compound.availableEquipment == Equipment.allCases)
        #expect(WatchExerciseFilter(mechanics: .compound, equipment: .barbell).apply(to: entries).map(\.name) == ["Squat"])
    }
}
