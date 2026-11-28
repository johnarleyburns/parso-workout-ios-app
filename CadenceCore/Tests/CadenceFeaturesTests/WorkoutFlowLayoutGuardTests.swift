import Foundation
import Testing

/// Structural guards for field-test layout decisions that are pure view
/// composition and therefore cannot be exercised by a headless `swift test`
/// render. They keep the shipped reading order and the "never force edit mode"
/// behavior from silently regressing.
struct WorkoutFlowLayoutGuardTests {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CadenceFeaturesTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // CadenceCore
            .deletingLastPathComponent() // repo root
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test func workoutPlanHasNoEditModeToggle() throws {
        let editor = try source("Cadence/Cadence/Features/Home/WorkoutPlanEditor.swift")
        #expect(!editor.contains("editor.edit"))
        #expect(!editor.contains("@State var isEditing"))
        #expect(!editor.contains("isEditing.toggle()"))
        #expect(!editor.contains("startInEditMode"))
    }

    @Test func addingAnExerciseNeverEntersEditMode() throws {
        let add = try source("Cadence/Cadence/Features/Home/WorkoutPlanEditor+SuggestExercise.swift")
        #expect(!add.contains("isEditing = true"))
        #expect(add.contains("func suggestExercise()"))
        #expect(!add.contains("Suggest Exercise…"))
    }

    private func position(of marker: String, in source: String) throws -> Int {
        let range = try #require(source.range(of: marker), "\(marker) not found")
        return source.distance(from: source.startIndex, to: range.lowerBound)
    }

    @Test func planAddExerciseLivesInTheTrailingToolbar() throws {
        let editor = try source("Cadence/Cadence/Features/Home/WorkoutPlanEditor.swift")
        // The list screen no longer carries an Add Exercise button; the
        // toolbar's "+" owns it, and Start stays at the bottom of the list.
        #expect(!editor.contains("suggestExerciseButton"))
        #expect(editor.contains("editor.addExercise"))
        #expect(editor.contains("suggestExercise()"))
        #expect(editor.contains("startButton"))
        #expect(editor.contains("LiveWorkoutVolumeSummary"))
    }

    @Test func workoutAddExerciseAndVolumeSummaryLiveInTheHeaderMenu() throws {
        let session = try source("Cadence/Cadence/Features/Train/SessionView+Rendering.swift")
        // Both moved out of the scrolling body: the toolbar owns Add Exercise
        // and the overflow owns the volume summary sheet.
        #expect(session.contains("sheet(isPresented: $volumeSummaryPresented)"))
        #expect(session.contains("navigationTitle(\"Volume Summary\")"))
        #expect(!session.contains("suggestExerciseButton"))
        let actions = try source("Cadence/Cadence/Features/Train/SessionView+Actions.swift")
        #expect(actions.contains("session.addExercise"))
        #expect(actions.contains("suggestExercise()"))
        #expect(actions.contains("session.volumeSummary"))
        #expect(actions.contains("volumeSummaryPresented = true"))
    }

    @Test func coolDownStartsWithoutASecondConfirmation() throws {
        let session = try source("Cadence/Cadence/Features/Train/SessionView+Rendering.swift")
        #expect(!session.contains("SessionCooldownConfirmationModifier"))
        #expect(session.contains("onCoolDown: startCooldownAfterDialog"))
    }

    @Test func guidedPhasesUseThreeEvenBottomActions() throws {
        let overlay = try source("Cadence/Cadence/Features/Shared/GuidedPhaseOverlay.swift")
        #expect(overlay.contains("finishTitle"))
        #expect(overlay.contains("finishSystemImage"))
        #expect(overlay.contains(".accessibilityIdentifier("))
        #expect(!overlay.contains("addFiveMinutes"))
    }

    @Test func planHistoryUsesCatalogKeysAndAllWeightSamples() throws {
        let planHistory = try source("Cadence/Cadence/Features/Home/WorkoutPlanPartnerHistory.swift")
        #expect(planHistory.contains("historyLookupKeys"))
        #expect(planHistory.contains("weightSamples"))
        #expect(!planHistory.contains("exercisesByName[name.lowercased()]"))
    }

    @Test func planEditorDoesNotRefreshOnEveryStoreNotification() throws {
        let editor = try source("Cadence/Cadence/Features/Home/WorkoutPlanEditor.swift")
        #expect(!editor.contains(".onReceive(NotificationCenter.default.publisher(for: .workoutHistoryChanged))"),
                "refreshing the plan from every history notification caused a flashing, unusable sheet")
        #expect(!editor.contains("onChange(of: allExercises.count)"))
        #expect(!editor.contains("onChange(of: allPeople.count)"))
    }

    @Test func watchSyncSendsTheEnteredWeightNotTheEffectiveLoad() throws {
        let watch = try source("CadenceCore/Sources/CadenceWorkoutFeatures/WatchStrengthFlowModel.swift")
        #expect(watch.contains("\"weight\": set.weight"))
        #expect(!watch.contains("\"weight\": set.effectiveLoadKg"))
    }
}
