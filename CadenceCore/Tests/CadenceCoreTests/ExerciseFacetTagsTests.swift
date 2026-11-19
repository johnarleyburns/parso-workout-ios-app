import Testing
@testable import CadenceCore

/// The exercise-detail facet chips must not repeat a label. `force` and `category`
/// both read "Push"/"Pull" for pressing/pulling movements — the reported duplicated
/// "Push" pill on Handstand Push-Ups.
struct ExerciseFacetTagsTests {

    @Test func pushForceAndPushCategoryCollapseToOnePill() {
        let tags = ExerciseFacetTagBuilder.tags(
            level: "beginner", equipment: .bodyweight, mechanics: .compound,
            force: .push, category: .push)
        #expect(tags == ["Beginner", "Bodyweight", "Compound", "Push"])
        #expect(tags.filter { $0 == "Push" }.count == 1, "no duplicate Push pill")
    }

    @Test func pullForceAndPullCategoryCollapse() {
        let tags = ExerciseFacetTagBuilder.tags(
            level: nil, equipment: .barbell, mechanics: .compound,
            force: .pull, category: .pull)
        #expect(tags == ["Barbell", "Compound", "Pull"])
    }

    @Test func distinctFacetsArePreserved() {
        // Bench Press: push force but "Push" category too → still one "Push"; the
        // other facets stay distinct.
        let tags = ExerciseFacetTagBuilder.tags(
            level: "intermediate", equipment: .barbell, mechanics: .compound,
            force: .push, category: .push)
        #expect(tags == ["Intermediate", "Barbell", "Compound", "Push"])
    }

    @Test func exerciseComputedTagsDelegateToBuilder() {
        let ex = Exercise(name: "Handstand Push-Up", category: .push,
                          equipment: .bodyweight, mechanics: .compound, force: .push,
                          level: "expert")
        #expect(ex.displayFacetTags.filter { $0 == "Push" }.count == 1)
        #expect(ex.displayFacetTags == ["Expert", "Bodyweight", "Compound", "Push"])
    }
}
