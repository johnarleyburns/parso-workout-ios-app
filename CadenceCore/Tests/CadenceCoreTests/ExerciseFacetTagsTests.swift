import XCTest
@testable import CadenceCore

/// The exercise-detail facet chips must not repeat a label. `force` and `category`
/// both read "Push"/"Pull" for pressing/pulling movements — the reported duplicated
/// "Push" pill on Handstand Push-Ups.
final class ExerciseFacetTagsTests: XCTestCase {

    func testPushForceAndPushCategoryCollapseToOnePill() {
        let tags = ExerciseFacetTagBuilder.tags(
            level: "beginner", equipment: .bodyweight, mechanics: .compound,
            force: .push, category: .push)
        XCTAssertEqual(tags, ["Beginner", "Bodyweight", "Compound", "Push"])
        XCTAssertEqual(tags.filter { $0 == "Push" }.count, 1, "no duplicate Push pill")
    }

    func testPullForceAndPullCategoryCollapse() {
        let tags = ExerciseFacetTagBuilder.tags(
            level: nil, equipment: .barbell, mechanics: .compound,
            force: .pull, category: .pull)
        XCTAssertEqual(tags, ["Barbell", "Compound", "Pull"])
    }

    func testDistinctFacetsArePreserved() {
        // Bench Press: push force but "Push" category too → still one "Push"; the
        // other facets stay distinct.
        let tags = ExerciseFacetTagBuilder.tags(
            level: "intermediate", equipment: .barbell, mechanics: .compound,
            force: .push, category: .push)
        XCTAssertEqual(tags, ["Intermediate", "Barbell", "Compound", "Push"])
    }

    func testExerciseComputedTagsDelegateToBuilder() {
        let ex = Exercise(name: "Handstand Push-Up", category: .push,
                          equipment: .bodyweight, mechanics: .compound, force: .push,
                          level: "expert")
        XCTAssertEqual(ex.displayFacetTags.filter { $0 == "Push" }.count, 1)
        XCTAssertEqual(ex.displayFacetTags, ["Expert", "Bodyweight", "Compound", "Push"])
    }
}
