import Foundation
import Testing
import CadenceCore
import CadencePhoneFeatures

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
        #expect(overlay.contains("finishTitle.isEmpty"))
        #expect(!overlay.contains("addFiveMinutes"))
        #expect(!overlay.contains("+5 min"))

        let warmup = try source("Cadence/Cadence/Features/Home/WarmupCover.swift")
        #expect(warmup.contains("finishSystemImage: \"chevron.forward.2\""))

        let session = try source("Cadence/Cadence/Features/Train/SessionView+RenderingSupport.swift")
        #expect(session.contains("finishTitle: \"\""))
        #expect(session.contains("finishSystemImage: \"stop.fill\""))
        #expect(session.contains("emphasis: .liveMetric"))
        #expect(session.contains("pauseShowsTitle: false"))
        #expect(!session.contains("finishTitle: String(localized: \"End\")"))
    }

    @Test func warmupCoversTheTabsAndHandsOffWithoutAHomeFlash() throws {
        let root = try source("Cadence/Cadence/App/RootTabView.swift")
        #expect(root.contains("WarmupPhaseCover(controller: warmupCover)"))
        #expect(root.contains(".environment(warmupCover)"))
        let scroll = try source("Cadence/Cadence/Features/Home/HomeView+DashboardScroll.swift")
        #expect(!scroll.contains(".fullScreenCover(isPresented: $warmupActive"))
        #expect(!scroll.contains("completePendingWarmupLaunch"))
        let launch = try source("Cadence/Cadence/Features/Home/HomeView+Warmup.swift")
        #expect(launch.contains("launch(.strength, startCue: startCue)"))
        #expect(launch.contains("asyncAfter"))
        #expect(launch.contains("warmupCover.dismiss()"))
    }

    @Test func workoutHeaderIsOneLiveUpdatingRow() throws {
        let header = try source("Cadence/Cadence/Features/Shared/WorkoutElapsedHeader.swift")
        #expect(header.contains("TimelineView"))
        #expect(!header.contains("WallClockLabel"))
        #expect(!header.contains("Timer.publish"))
        // Elapsed, live HR and Work/Rest share one size.
        #expect(header.contains("private func intervalTimerButton"))
        #expect(header.contains(".font(.headline.weight(.semibold))"))
        #expect(!header.contains("design: .rounded"))
        #expect(!header.contains(".subheadline.weight(.bold)"))
        #expect(header.contains("intervalTimerButton(now: now)"))
        #expect(header.contains("timers.beginRest(now: ref)"))
        #expect(header.contains("timers.beginWork(now: ref)"))
        #expect(!header.contains("Text(\"Paused\")"))
        #expect(!header.contains("Text(verbatim: \"/\")"))
        #expect(header.contains("session.timer.interval"))
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
        // Pause and End are icon-only; accessibility keeps the words.
        #expect(bar.contains("Image(systemName: pause.systemImage)"))
        #expect(bar.contains("Image(systemName: WorkoutDockPresenter.endSystemImage)"))
        #expect(!bar.contains("Label(LocalizedStringKey(pause.title)"))
        #expect(bar.contains(".accessibilityLabel(pause.title)"))
    }

    @Test func connectHeartRateKeepsContinueClose() throws {
        let hr = try source("Cadence/Cadence/Features/Shared/PreWorkoutHRView.swift")
        #expect(hr.contains("Spacer(minLength: 12).frame(maxHeight: 40)"))
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
        // Show Deleted keeps the normal timeline and only adds the red subtitle.
        #expect(!history.contains("legacyDeletedList"))
        #expect(history.contains("includeDeleted: showDeleted"))
        #expect(history.contains("HomeWeekWorkoutRow(entry: entry"))
        let row = try source("Cadence/Cadence/Features/Home/HomeWhatYouDidRow.swift")
        #expect(row.contains("if content.isDeleted"))
        #expect(row.contains("Text(\"Deleted\")"))
        #expect(row.contains(".foregroundStyle(.red)"))
    }

    @Test func pauseIsABigBlurredSurfaceWithResume() throws {
        let rendering = try source("Cadence/Cadence/Features/Train/SessionView+RenderingSupport.swift")
        #expect(rendering.contains("active.isPaused"))
        #expect(rendering.contains(".ultraThinMaterial"))
        #expect(rendering.contains("Text(\"PAUSED\")"))
        #expect(rendering.contains("session.paused.resume"))
        #expect(!rendering.contains("Text(\"Paused\").font(.caption2"))
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

    @Test func warmupUsesCardioLayoutAndSinglePlusButtons() throws {
        let overlay = try source("Cadence/Cadence/Features/Shared/GuidedPhaseOverlay.swift")
        #expect(overlay.contains("enum Emphasis"))
        #expect(overlay.contains("case liveMetric"))
        #expect(overlay.contains("pauseShowsTitle"))
        #expect(overlay.contains("Image(systemName: \"plus\")"))
        #expect(!overlay.contains("Label(\"1 min\""))
        #expect(!overlay.contains("Label(\"+1 min\""))

        let home = try source("Cadence/Cadence/Features/Home/WarmupCover.swift")
        #expect(home.contains("emphasis: .liveMetric"))
        #expect(home.contains("pauseShowsTitle: false"))
        #expect(home.contains("GuidedPhaseLiveHRView(idPrefix: \"warmup\")"))

        let hr = try source("Cadence/Cadence/Features/Train/GuidedPhaseLiveHRView.swift")
        #expect(hr.contains("LiveHRBigView("))
        #expect(hr.contains("CardioMath.hrZone"))
        // Guided phases never show reconnect copy or actions.
        #expect(hr.contains("connectionNote: nil"))
        #expect(!hr.contains("Reconnect Apple Watch HR"))
    }

    @Test func addSetEditorIsFullHeightAndFocused() throws {
        let editor = try source("Cadence/Cadence/Features/Train/InlineSetEditorView.swift")
        let panels = try source("Cadence/Cadence/Features/Train/InlineSetEditorView+Panels.swift")
        let combined = editor + panels
        #expect(editor.contains(".custom(SetEditorSheetDetent.self)"))
        let shared = try source("Cadence/Cadence/Features/Train/SessionViewShared.swift")
        #expect(shared.contains("context.maxDetentValue - 72"))
        #expect(combined.contains("historyLastTimeText"))
        #expect(!editor.contains("Who did this set?"))
        #expect(!editor.contains("How hard did the set feel?"))
        #expect(!editor.contains("setEditor.weightSource"))
        #expect(!editor.contains("CitationLink("))
        #expect(!editor.contains("Button(\"None\")"))
        #expect(!editor.contains("Text(\"Type\").font(.caption)"))

        // The set gauge replaces the separate "Set 1 of 3" subtitle row.
        #expect(editor.contains("config.setTotal"))
        #expect(editor.contains("setEditor.setGauge"))
        #expect(!editor.contains("Text(config.setNumberText)"))

        // History, partner entry and effort live in the header overflow menu
        // and open as sheets; the body carries only weight, reps and Log Set.
        #expect(editor.contains("setEditor.menu"))
        #expect(editor.contains("setEditor.menu.history"))
        #expect(editor.contains("setEditor.menu.partner"))
        #expect(editor.contains("setEditor.menu.effort"))
        #expect(editor.contains("setProgressRing"))
        #expect(combined.contains("Show History"))
        #expect(combined.contains("setEditor.history.toggle"))

        // The separate + Add Partner row is gone; the Partner sheet owns it.
        #expect(!editor.contains("＋ Add Partner"))
        #expect(combined.contains("Add Partner…"))

        // Weight steppers sit beside the value; plate buttons live on the title
        // row and the value itself is smaller.
        let minus = try #require(editor.range(of: "weightStepButton(\"−\""))
        let value = try #require(editor.range(of: "setEditor.weightValue"))
        let plus = try #require(editor.range(of: "weightStepButton(\"+\""))
        #expect(minus.lowerBound < value.lowerBound && value.lowerBound < plus.lowerBound)
        #expect(editor.contains("ScrollViewReader"))
        #expect(editor.contains("proxy.scrollTo(increment, anchor: .center)"))
        #expect(editor.contains("config.unit == .pounds ? 5 : 2.5"))
        #expect(!editor.contains("scaledSystemFont(52"))
        #expect(editor.contains("scaledSystemFont(40"))
        #expect(editor.contains("setEditor.weight.increment"))

        // Reps uses the same step-button component as Weight.
        #expect(editor.contains("weightStepButton(\"−\", label: \"Decrease reps\""))
        #expect(editor.contains("weightStepButton(\"+\", label: \"Increase reps\""))

        // Effort is one number with +/- and no chooser grid or helper prose.
        #expect(combined.contains("setEditor.effort.minus"))
        #expect(combined.contains("setEditor.effort.plus"))
        #expect(combined.contains("setEditor.effort.value"))
        #expect(!editor.contains("LazyVGrid"))

        #expect(ExpandedSetDraftModel.increments(for: .pounds).contains(5))
    }

    @Test func pendingSetRowsUseAChevronAndNeverLogDirectly() throws {
        let card = try source("Cadence/Cadence/Features/Train/ExerciseCardView.swift")
        #expect(card.contains("Image(systemName: \"chevron.right\")"))
        #expect(card.contains("accessibilityAction(named: \"Edit set\")"))
        #expect(!card.contains("onLogPending"))
        #expect(!card.contains("session.set.log"))
        #expect(!card.contains("plus.circle"))

        let redesign = try source("Cadence/Cadence/Features/Train/SessionView+RedesignUI.swift")
        #expect(!redesign.contains("onLogPending"))
        #expect(!redesign.contains("logPendingSet("))
    }

    @Test func setEditorRosterAlwaysKeepsTheOwnerForHistory() throws {
        let session = try source("Cadence/Cadence/Features/Train/SessionView.swift")
        #expect(session.contains("guard !entries.contains(where: \\.isMe) else { return entries }"))
        #expect(session.contains("RosterEntry(personID: nil, name: \"Me\", isMe: true)"))
    }
}
