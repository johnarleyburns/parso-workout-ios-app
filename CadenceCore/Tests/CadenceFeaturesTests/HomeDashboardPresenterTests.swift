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

    func testVolumeStatusUsesBelowProductiveBoundary() throws {
        let row = try dashboard(chestSets: 7, now: Date()).volume.first { $0.part == .chest }
        XCTAssertEqual(row?.status, .belowStartingRange)
        XCTAssertEqual(row?.rangeStatus, "Below starting range")
    }

    func testVolumeStatusUsesProductiveBoundaryIncludingMAV() throws {
        let atStarting = try dashboard(chestSets: 8, now: Date()).volume.first { $0.part == .chest }
        let atProductiveCeiling = try dashboard(chestSets: 16, now: Date()).volume.first { $0.part == .chest }
        XCTAssertEqual(atStarting?.status, .productive)
        XCTAssertEqual(atProductiveCeiling?.status, .productive)
    }

    func testVolumeStatusFlagsAboveRecoveryBoundary() throws {
        let row = try dashboard(chestSets: 23, now: Date()).volume.first { $0.part == .chest }
        XCTAssertEqual(row?.status, .aboveRecoveryRange)
        XCTAssertEqual(row?.rangeStatus, "Above recovery range")
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

    func testVolumeCoverageCountsOnlyProductiveGreenBodyParts() throws {
        let state = try dashboard(chestSets: 8, now: Date())
        XCTAssertEqual(state.volume.first?.displayName, "Legs")
        XCTAssertEqual(state.volumeCoverage.displayText, "1/8 body parts")
        XCTAssertEqual(state.volumeCoverage.completed, 1)
        XCTAssertEqual(state.volumeCoverage.normalized, 0.125, accuracy: 0.001)
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
