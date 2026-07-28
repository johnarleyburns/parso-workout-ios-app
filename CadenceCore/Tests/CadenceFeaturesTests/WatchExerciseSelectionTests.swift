import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchExerciseSelectionTests: XCTestCase {

    func testDefaultSectionsUseSharedBodyPartTaxonomyAndOtherRows() {
        let exercises = [
            Exercise(name: "Bench Press", muscleGroups: ["chest"], primaryMuscles: ["chest"]),
            Exercise(name: "Cable Row", muscleGroups: ["lats"], primaryMuscles: ["lats"]),
            Exercise(name: "Dumbbell Curl", muscleGroups: ["biceps"], primaryMuscles: ["biceps"]),
            Exercise(name: "Cable Pressdown", muscleGroups: ["triceps"], primaryMuscles: ["triceps"]),
            Exercise(name: "Standing Calf Raise", muscleGroups: ["calves"], primaryMuscles: ["calves"]),
            Exercise(name: "Crunch", muscleGroups: ["abs"], primaryMuscles: ["abs"]),
            Exercise(name: "Back Squat", muscleGroups: ["quads", "glutes"], primaryMuscles: ["quads", "glutes"]),
            Exercise(name: "Lateral Raise", muscleGroups: ["delts"], primaryMuscles: ["delts"]),
        ]

        let sections = WatchExerciseSelection.defaultSections(
            exercises: exercises,
            recent: [exercises[2]],
            popularNames: ["Bench Press", "Back Squat"],
            perBodyPartLimit: 2
        )

        XCTAssertEqual(sections.first?.title, "My Last Exercises")
        XCTAssertEqual(sections.first?.exerciseNames, ["Dumbbell Curl"])
        XCTAssertTrue(sections.contains { $0.title == "Popular Exercises" && $0.exerciseNames == ["Bench Press", "Back Squat"] })
        XCTAssertFalse(sections.contains { $0.title == "Arms" })

        for part in BodyPart.allCases {
            let section = sections.first { $0.title == part.displayName }
            XCTAssertNotNil(section, "Missing \(part.displayName)")
            XCTAssertEqual(section?.otherBodyPart, part)
        }

        XCTAssertTrue(sections.first { $0.title == "Biceps" }?.exerciseNames.contains("Dumbbell Curl") == true)
        XCTAssertTrue(sections.first { $0.title == "Triceps" }?.exerciseNames.contains("Cable Pressdown") == true)
        XCTAssertTrue(sections.first { $0.title == "Calves" }?.exerciseNames.contains("Standing Calf Raise") == true)
    }

    func testFullListFiltersAndSortsByBodyPart() {
        let exercises = [
            Exercise(name: "Z Calf Raise", muscleGroups: ["calves"], primaryMuscles: ["calves"]),
            Exercise(name: "A Calf Raise", muscleGroups: ["calves"], primaryMuscles: ["calves"]),
            Exercise(name: "Bench Press", muscleGroups: ["chest"], primaryMuscles: ["chest"]),
        ]

        XCTAssertEqual(WatchExerciseSelection.fullList(for: .calves, exercises: exercises),
                       ["A Calf Raise", "Z Calf Raise"])
    }
}
