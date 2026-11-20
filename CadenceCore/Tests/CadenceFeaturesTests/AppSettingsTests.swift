import Testing
import Foundation
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// AppSettings (the "SettingsStore" lift, test-pyramid Phase 2) is now headlessly
/// testable via its injected storage. Covers persistence, defaults, and the
/// lossless preferences round-trip (FR-6.2) without touching the real
/// preferences daemon.
struct AppSettingsTests {

    private func freshStore() -> InMemoryDefaultsStore {
        InMemoryDefaultsStore()
    }

    @Test func defaultsWhenEmpty() {
        let s = AppSettings(storage: freshStore())
        #expect(s.unit == SettingsDefault.unit)
        #expect(s.distanceUnit == SettingsDefault.distanceUnit)
        #expect(s.formula == SettingsDefault.oneRepMaxFormula)
        #expect(s.restSeconds == SettingsDefault.restSeconds)
    }

    @Test func legacyOnboardingFlagDoesNotChangeSettings() {
        let a = freshStore(); a.set(true, forKey: "settings.hasCompletedOnboarding"); a.set("pounds", forKey: "settings.unit")
        let b = freshStore(); b.set(false, forKey: "settings.hasCompletedOnboarding"); b.set("pounds", forKey: "settings.unit")
        #expect(AppSettings(storage: a).unit == AppSettings(storage: b).unit)
        #expect(AppSettings(storage: a).restSeconds == AppSettings(storage: b).restSeconds)
    }

    @Test func mutationPersistsAcrossInstances() {
        let d = freshStore()
        let a = AppSettings(storage: d)
        a.unit = .pounds
        a.distanceUnit = .miles
        a.restSeconds = 120
        a.trainingGoal = .strength
        a.coachHidden = true
        a.hasSeenFirstSetCoachMark = true
        a.hasSeenAlwaysOnTip = true

        let b = AppSettings(storage: d)
        #expect(b.unit == .pounds)
        #expect(b.distanceUnit == .miles)
        #expect(b.restSeconds == 120)
        #expect(b.trainingGoal == .strength)
        #expect(b.coachHidden)
        #expect(b.hasSeenFirstSetCoachMark)
        #expect(b.hasSeenAlwaysOnTip)
    }

    @Test func alwaysOnTipShowsOnlyOnceAfterWatchRequested() {
        #expect(!PreWorkoutHRPresenter.shouldShowAlwaysOnTip(watchRequested: false, hasSeenTip: false))
        #expect(PreWorkoutHRPresenter.shouldShowAlwaysOnTip(watchRequested: true, hasSeenTip: false))
        #expect(!PreWorkoutHRPresenter.shouldShowAlwaysOnTip(watchRequested: true, hasSeenTip: true))
        #expect(!AppSettings(storage: freshStore()).hasSeenAlwaysOnTip)
    }

    @Test func favoriteRoutineToggle() {
        let s = AppSettings(storage: freshStore())
        #expect(!s.isRoutineFavorite("ppl"))
        s.toggleFavoriteRoutine("ppl")
        #expect(s.isRoutineFavorite("ppl"))
        s.toggleFavoriteRoutine("ppl")
        #expect(!s.isRoutineFavorite("ppl"))
    }

    @Test func coachScheduleJSONPersistence() {
        let d = freshStore()
        let a = AppSettings(storage: d)
        a.coachSchedulePreferences = CoachSchedulePreferences.default
            .withTwoADays(true)
            .withDesiredSetsPerExercise(4)
        let b = AppSettings(storage: d)
        #expect(b.coachSchedulePreferences.allowsTwoADays)
        #expect(b.coachSchedulePreferences.desiredSetsPerExercise == 4)
    }

    @Test func exportImportRoundTrip() {
        let src = AppSettings(storage: freshStore())
        src.unit = .pounds
        src.distanceUnit = .miles
        src.experienceLevel = .advanced
        src.userAge = 41
        src.warmupMinutes = 7
        src.celebrationStyle = .quiet
        src.restAlertMode = .alarm
        src.coachSchedulePreferences = src.coachSchedulePreferences.withDesiredSetsPerExercise(4)
        let snapshot = src.exportPreferences()

        let dst = AppSettings(storage: freshStore())
        dst.applyImportedPreferences(snapshot)
        #expect(dst.unit == .pounds)
        #expect(dst.distanceUnit == .miles)
        #expect(dst.experienceLevel == .advanced)
        #expect(dst.userAge == 41)
        #expect(dst.warmupMinutes == 7)
        #expect(dst.celebrationStyle == .quiet)
        #expect(dst.restAlertMode == .alarm)
        #expect(dst.coachSchedulePreferences.desiredSetsPerExercise == 4)
    }
}
