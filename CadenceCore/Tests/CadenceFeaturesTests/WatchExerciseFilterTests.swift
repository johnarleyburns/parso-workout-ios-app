import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchExerciseFilterTests: XCTestCase {

    func testFilterNarrowsByMechanicsAndEquipment() {
        let entries = [
            ExerciseCatalogEntry(id: UUID(), name: "Squat", equipmentValue: .barbell, mechanicsValue: .compound),
            ExerciseCatalogEntry(id: UUID(), name: "Leg Extension", equipmentValue: .machine, mechanicsValue: .isolation),
            ExerciseCatalogEntry(id: UUID(), name: "Goblet Squat", equipmentValue: .dumbbell, mechanicsValue: .compound),
        ]
        XCTAssertEqual(WatchExerciseFilter().apply(to: entries).count, 3)
        XCTAssertFalse(WatchExerciseFilter().isActive)
        let compound = WatchExerciseFilter(mechanics: .compound)
        XCTAssertEqual(compound.apply(to: entries).map(\.name), ["Squat", "Goblet Squat"])
        XCTAssertEqual(compound.availableEquipment, Equipment.allCases)
        XCTAssertEqual(WatchExerciseFilter(mechanics: .compound, equipment: .barbell).apply(to: entries).map(\.name), ["Squat"])
    }
}
