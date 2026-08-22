import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

final class HomeDashboardPresenterTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func dashboard(chestSets: Int, now: Date) throws -> HomeDashboardState {
        let context = try makeContext()
        let session = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-3_600), in: context)
        let exercise = try WorkoutRepository.findOrCreateExercise(
            named: "Dashboard Bench", primaryMuscles: ["chest"], in: context)
        for _ in 0..<chestSets {
            _ = try WorkoutRepository.addSet(
                to: session, exercise: exercise, weightKg: 60, reps: 5,
                rpe: 7, in: context)
        }
        try context.save()
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let snapshot = CoachSnapshotBuilder.build(
            sessions: sessions, cardio: [], assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: .default, profile: .empty, now: now)
        return HomeDashboardPresenter.make(
            snapshot: snapshot, schedule: .default, goal: .strength,
            experience: .intermediate, userAge: nil)
    }

    func testVolumeRowsUseTheSharedWeeklySetZonesAndCitation() throws {
        let below = try dashboard(chestSets: 3, now: Date()).volume.first { $0.part == .chest }
        let building = try dashboard(chestSets: 4, now: Date()).volume.first { $0.part == .chest }
        let productive = try dashboard(chestSets: 8, now: Date()).volume.first { $0.part == .chest }
        let above = try dashboard(chestSets: 13, now: Date()).volume.first { $0.part == .chest }

        XCTAssertEqual(below?.zone, .belowMinimum)
        XCTAssertEqual(building?.zone, .building)
        XCTAssertEqual(productive?.zone, .productive)
        XCTAssertEqual(above?.zone, .aboveMaximum)
        XCTAssertEqual(above?.rangeText, "Above 12-set maximum")
        XCTAssertEqual(productive?.normalized ?? 0, 8.0 / 12.0, accuracy: 0.001)
        XCTAssertEqual(above?.normalized, 1)
        XCTAssertNotNil(CitationRegistry.citation(forId: productive?.citationID ?? ""))
    }

    func testProgressStatusChangesOnlyAtTarget() {
        let below = HomeDashboardState.Progress(
            completed: 1, target: 2, displayText: "1 of 2", normalized: 0.5)
        let atTarget = HomeDashboardState.Progress(
            completed: 2, target: 2, displayText: "2 of 2", normalized: 1)
        let aboveTarget = HomeDashboardState.Progress(
            completed: 3, target: 2, displayText: "3 of 2", normalized: 1)
        XCTAssertFalse(below.isAtOrAboveTarget)
        XCTAssertTrue(atTarget.isAtOrAboveTarget)
        XCTAssertTrue(aboveTarget.isAtOrAboveTarget)
    }

    func testVolumeSummaryUsesMeanCappedSetsAcrossMuscleGroups() throws {
        let state = try dashboard(chestSets: 8, now: Date())
        XCTAssertEqual(state.volume.map(\.displayName), ["Back", "Biceps", "Calves", "Chest", "Core", "Legs", "Shoulders", "Triceps"])
        XCTAssertEqual(state.volumeCoverage.displayText, "1 avg sets")
        XCTAssertEqual(state.volumeCoverage.completed, 1)
        XCTAssertEqual(state.volumeCoverage.normalized, 1.0 / 12.0, accuracy: 0.001)
    }

    func testSuggestionToneMapsProgressWarningsAndInformation() {
        let make: (HomeSuggestion.Category) -> HomeSuggestion = { category in
            HomeSuggestion(id: "tone-\(category.rawValue)", category: category,
                           title: "Suggestion", message: "Details", citationID: nil,
                           sourceClaimKey: "tone-\(category.rawValue)", priority: 0, confidence: 100)
        }
        XCTAssertEqual(make(.progress).tone, .neutral)
        XCTAssertEqual(make(.weeklyDeficit).tone, .warning)
        XCTAssertEqual(make(.volumeRecovery).tone, .warning)
        XCTAssertEqual(make(.safety).tone, .warning)
        XCTAssertEqual(make(.planAction).tone, .neutral)
    }

    func testSuggestionToneMapsProductiveVolumeToNeutral() {
        let suggestion = HomeSuggestion(
            id: "volume.chest", category: .volumeRecovery,
            title: "Chest volume is productive", message: "8 sets this week",
            citationID: CitationRegistry.volumeDoseResponse.id,
            sourceClaimKey: "insight:volume.chest", priority: 0, confidence: 100)
        XCTAssertEqual(suggestion.tone, .warning)
    }

    // MARK: - Muscles (field test 2026-08-19 #8)

    func testMuscleRowsCoverEveryTrackedMuscle() throws {
        let muscles = try dashboard(chestSets: 4, now: Date()).muscles
        XCTAssertEqual(Set(muscles.map(\.muscleID)), Set(MuscleCatalog.all.map(\.id)),
                       "Every catalog muscle needs a line, including the ones at zero")
    }

    func testMuscleRowsUseTheSharedZonesAndKeepFractionalSets() {
        let rows = HomeDashboardPresenter.muscleRows(setsByMuscle: [
            "chest": 3.5, "lats": 4, "glutes": 8, "quads": 12.5,
        ])
        XCTAssertEqual(rows.first { $0.muscleID == "chest" }?.zone, .belowMinimum)
        XCTAssertEqual(rows.first { $0.muscleID == "lats" }?.zone, .building)
        XCTAssertEqual(rows.first { $0.muscleID == "glutes" }?.zone, .productive)
        let quads = rows.first { $0.muscleID == "quads" }
        XCTAssertEqual(quads?.zone, .aboveMaximum)
        XCTAssertEqual(quads?.normalized, 1)
        XCTAssertEqual(rows.first { $0.muscleID == "chest" }?.sets, 3.5)
        XCTAssertEqual(rows.first { $0.muscleID == "chest" }?.normalized ?? 0, 3.5 / 12, accuracy: 0.001)
        XCTAssertNotNil(CitationRegistry.citation(forId: quads?.citationID ?? ""))
    }

    func testMuscleRowsAreOrderedAlphabeticallyAndTitleCased() throws {
        let muscles = try dashboard(chestSets: 4, now: Date()).muscles
        XCTAssertEqual(muscles.map(\.displayName), ["Abductors", "Abs", "Adductors", "Biceps", "Calves", "Chest", "Delts", "Forearms", "Front Delts", "Glutes", "Hamstrings", "Hip Flexors", "Lats", "Lower Back", "Obliques", "Quads", "Rear Delts", "Rhomboids", "Traps", "Triceps", "Upper Chest"])
        XCTAssertTrue(muscles.allSatisfy { $0.displayName.first?.isUppercase == true })
    }

    func testMuscleSummaryUsesMeanCappedSetsAcrossEveryMuscle() throws {
        let state = try dashboard(chestSets: 12, now: Date())
        XCTAssertEqual(state.muscleCoverage.completed, 12.0 / Double(MuscleCatalog.all.count), accuracy: 0.001)
        XCTAssertEqual(state.muscleCoverage.displayText, "0.6 avg sets")
        XCTAssertEqual(state.muscleCoverage.normalized, 1.0 / Double(MuscleCatalog.all.count), accuracy: 0.001)
    }

    // MARK: - Cardio minutes (field test 2026-08-19 #7)

    func testCardioDetailExplainsTheModerateEquivalentWeighting() {
        let detail = HomeDashboardState.CardioDetail(
            loggedMinutes: 80, easyMinutes: 0, moderateMinutes: 2, vigorousMinutes: 78,
            moderateEquivalentMinutes: 158, targetMinutes: 150,
            citationID: CitationRegistry.ekelundActivityMortality2016.id)
        XCTAssertEqual(detail.summary, "80 min logged counts as 158 moderate-equivalent min.")
        XCTAssertTrue(detail.explanation.contains("Vigorous work counts double"))
        XCTAssertEqual(detail.lines.map { $0.label }, ["Moderate", "Vigorous"])
        XCTAssertEqual(detail.lines.last?.credit, "156 min credited")
        XCTAssertNotNil(CitationRegistry.citation(forId: detail.citationID),
                        "The cardio explanation must resolve to a real, navigable study")
    }

    func testCardioDetailWithOnlyModerateWorkNeedsNoWeightingCaveat() {
        let detail = HomeDashboardState.CardioDetail(
            loggedMinutes: 60, easyMinutes: 0, moderateMinutes: 60, vigorousMinutes: 0,
            moderateEquivalentMinutes: 60, targetMinutes: 150,
            citationID: CitationRegistry.ekelundActivityMortality2016.id)
        XCTAssertEqual(detail.summary, "60 min logged this week.")
    }

    func testCardioDetailIsPopulatedFromTheWeeklyBalance() throws {
        let dash = try dashboard(chestSets: 1, now: Date())
        XCTAssertEqual(dash.cardioDetail.targetMinutes, 150)
        XCTAssertEqual(dash.cardioDetail.loggedMinutes, 0)
        XCTAssertEqual(dash.cardioDetail.moderateEquivalentMinutes, dash.cardio.completed)
    }

    func testVisibleSuggestionsCapsCollapsedCardAndRestoresExpandedItems() {
        let items = (0..<5).map { index in
            HomeSuggestion(id: "suggestion-\(index)", category: .progress,
                           title: "Suggestion \(index)", message: "Details", citationID: nil,
                           sourceClaimKey: "suggestion-\(index)", priority: 0, confidence: 100)
        }
        XCTAssertEqual(HomeDashboardPresenter.visibleSuggestions(items, expanded: false).map(\.id),
                       items.prefix(1).map(\.id))
        XCTAssertEqual(HomeDashboardPresenter.visibleSuggestions(items, expanded: true), items)
    }
}
