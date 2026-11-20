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
        #expect(!editor.contains("isEditing"))
        #expect(!editor.contains("startInEditMode"))
    }

    @Test func addingAnExerciseNeverEntersEditMode() throws {
        let add = try source("Cadence/Cadence/Features/Home/WorkoutPlanEditor+SuggestExercise.swift")
        #expect(!add.contains("isEditing = true"))
        #expect(add.contains("String(localized: \"Add Exercise\")"))
        #expect(!add.contains("Suggest Exercise…"))
    }

    @Test func addExerciseSitsBelowVolumeAndImmediatelyAboveStart() throws {
        let editor = try source("Cadence/Cadence/Features/Home/WorkoutPlanEditor.swift")
        let volume = try #require(editor.range(of: "LiveWorkoutVolumeSummary"))
        let add = try #require(editor.range(of: "suggestExerciseButton"))
        let start = try #require(editor.range(of: "startButton"))
        #expect(volume.lowerBound < add.lowerBound)
        #expect(add.lowerBound < start.lowerBound)
    }

    @Test func workoutAddExerciseFollowsVolumeSummary() throws {
        let session = try source("Cadence/Cadence/Features/Train/SessionView+Rendering.swift")
        let volume = try #require(session.range(of: "LiveWorkoutVolumeSummary"))
        let add = try #require(session.range(of: "suggestExerciseButton"))
        #expect(volume.lowerBound < add.lowerBound)
    }

    @Test func coolDownStartsWithoutASecondConfirmation() throws {
        let session = try source("Cadence/Cadence/Features/Train/SessionView+Rendering.swift")
        #expect(!session.contains("SessionCooldownConfirmationModifier"))
        #expect(session.contains("onCoolDown: startCooldownAfterDialog"))
    }

    @Test func guidedPhasesOfferFiveMinutesAndAnEndAction() throws {
        let overlay = try source("Cadence/Cadence/Features/Shared/GuidedPhaseOverlay.swift")
        #expect(overlay.contains("addFiveMinutes"))
        #expect(overlay.contains("finishTitle"))
    }
}
