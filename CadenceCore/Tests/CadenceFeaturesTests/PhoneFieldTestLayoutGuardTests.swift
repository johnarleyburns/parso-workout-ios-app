import Foundation
import Testing

/// Structural guards for the phone field-test batch. These cover SwiftUI
/// composition and notification wiring that the headless suite cannot render.
struct PhoneFieldTestLayoutGuardTests {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test func findExerciseMovesScopeTabsIntoTheFilterMenu() throws {
        let picker = try source("Cadence/Cadence/Features/Train/ExercisePickerView.swift")
        #expect(!picker.contains("tabPicker"))
        #expect(picker.contains("listSectionSpacing(.compact)"))

        let controls = try source("Cadence/Cadence/Features/Train/ExercisePickerView+Controls.swift")
        #expect(controls.contains("Picker(\"Show\""))
        #expect(controls.contains("Text(\"Browse\").tag"))
        #expect(controls.contains("Text(\"Recents\").tag"))
        #expect(controls.contains("Text(\"Popular\").tag"))
        #expect(controls.contains("Divider()"))
        #expect(!controls.contains("Text(\"Any\").tag"))
        #expect(!controls.contains("var tabPicker"))
    }

    @Test func planAddExerciseUsesTheWorkoutRepStructure() throws {
        let editing = try source("Cadence/Cadence/Features/Home/WorkoutPlanEditor+Editing.swift")
        #expect(editing.contains("WorkoutPlanRepSchemeOptions.templateSets(following:"))
        #expect(editing.contains("seededHistoryNames.insert(exercise.name)"))
    }

    @Test func warmupAndCooldownUseThreeEvenBottomButtons() throws {
        let overlay = try source("Cadence/Cadence/Features/Shared/GuidedPhaseOverlay.swift")
        #expect(overlay.contains("finishSystemImage"))
        #expect(!overlay.contains("addFiveMinutes"))
        #expect(!overlay.contains("+5 min"))

        let home = try source("Cadence/Cadence/Features/Home/HomeView+DashboardOverlays.swift")
        #expect(home.contains("finishSystemImage: \"chevron.forward.2\""))

        let session = try source("Cadence/Cadence/Features/Train/SessionView+RenderingSupport.swift")
        #expect(session.contains("finishTitle: String(localized: \"End\")"))
        #expect(!session.contains("chevron.forward.2"))
    }

    @Test func warmupIsPresentedFullScreenWithoutTheTabBar() throws {
        let scroll = try source("Cadence/Cadence/Features/Home/HomeView+DashboardScroll.swift")
        #expect(scroll.contains(".fullScreenCover(isPresented: $warmupActive"))
        #expect(scroll.contains("completePendingWarmupLaunch"))
        #expect(scroll.contains("interactiveDismissDisabled"))
        let overlays = try source("Cadence/Cadence/Features/Home/HomeView+DashboardOverlays.swift")
        #expect(!overlays.contains("if warmupActive"))
    }

    @Test func workoutHeaderIsOneLiveUpdatingRow() throws {
        let header = try source("Cadence/Cadence/Features/Shared/WorkoutElapsedHeader.swift")
        #expect(header.contains("TimelineView"))
        #expect(!header.contains("WallClockLabel"))
        #expect(!header.contains("Timer.publish"))
        #expect(header.contains(".font(.system(.title3"))
        #expect(header.contains("timerButton(.work"))
        #expect(header.contains("timerButton(.rest"))
    }

    @Test func liveHRInfoLivesInTheWorkoutMenuOnlyOnce() throws {
        let inline = try source("Cadence/Cadence/Features/Train/SessionInfoSheets.swift")
        #expect(!inline.contains("session.hr.info"))
        #expect(!inline.contains("alert(\"Receiving live HR\""))
        let actions = try source("Cadence/Cadence/Features/Train/SessionView+Actions.swift")
        #expect(actions.contains("showHRInfo = true"))
        let rendering = try source("Cadence/Cadence/Features/Train/SessionView+Rendering.swift")
        #expect(rendering.contains(".confirmationDialog(\"Heart Rate\""))
    }

    @Test func workoutDockButtonsUseTheCompactHeight() throws {
        let bar = try source("Cadence/Cadence/Features/Shared/WorkoutControlBar.swift")
        #expect(bar.contains("compact: true"))
        #expect(bar.contains("compactTargetHeight"))
        #expect(!bar.contains("minimumTargetHeight"))
    }

    @Test func addSetSitsOnTheWeightRepsHeaderRow() throws {
        let card = try source("Cadence/Cadence/Features/Train/ExerciseCardView.swift")
        let header = try #require(card.range(of: "private var setColumnHeader"))
        let actions = try #require(card.range(of: "private var actionButtons"))
        let headerText = String(card[header.lowerBound..<actions.lowerBound])
        #expect(headerText.contains("onAddSet()"))
        #expect(headerText.contains("set.add."))
    }

    @Test func volumeSummaryIgnoresHistoricalUnknownPartners() throws {
        let summary = try source("Cadence/Cadence/Features/Train/LiveWorkoutVolumeSummary.swift")
        #expect(summary.contains("unknownKeys = Set(currentSets"))
        #expect(!summary.contains("currentSets + weeklySets"))
    }

    @Test func historySwipeDeletesImmediatelyAndShowsDeletedText() throws {
        let history = try source("Cadence/Cadence/Features/History/HistoryView.swift")
        #expect(history.contains("deleteImmediately"))
        #expect(history.contains("Button(role: .destructive) { deleteImmediately(entry) }"))
        #expect(history.contains("Text(control.title)"))
        #expect(history.contains("NotificationCenter.default.post(name: .workoutHistoryChanged"))
    }

    @Test func watchConfirmedToastIsNotRepeated() throws {
        let root = try source("Cadence/Cadence/App/RootTabView.swift")
        #expect(root.contains("if case .upToDate = state { return }"))
    }

    @Test func cardioBPMGetsAContrastingBackdrop() throws {
        let hr = try source("Cadence/Cadence/Features/Cardio/LiveHRBigView.swift")
        #expect(hr.contains("Color.black.opacity"))
    }

    @Test func settingsCanArchiveTrainingPartners() throws {
        let settings = try source("Cadence/Cadence/Features/Settings/SettingsView.swift")
        #expect(settings.contains("TrainingPartnersSettingsSection()"))
        let partners = try source("Cadence/Cadence/Features/Settings/TrainingPartnersSettingsSection.swift")
        #expect(partners.contains("isArchived = true"))
        #expect(partners.contains("settings.section.partners"))
        #expect(partners.contains("Query(filter: #Predicate<Person>"))
        let model = try source("CadenceCore/Sources/CadenceCore/Models.swift")
        #expect(model.contains("var isArchived: Bool = false"))
    }
}
