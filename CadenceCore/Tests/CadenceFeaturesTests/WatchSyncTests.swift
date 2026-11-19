import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore
import CadencePhoneFeatures

struct WatchSyncTests {

    // MARK: - WeightIncrement

    @Test func poundPlateOptionsAndDecimalCrown() {
        let inc = WeightIncrement(unit: .pounds)
        #expect(inc.plateOptions == [45, 35, 25, 10, 5, 2.5])
        #expect(inc.crownDetent == 0.1)
        #expect(inc.range == 0...650)
    }

    @Test func chipLabel_formatsHalfIncrements() {
        let inc = WeightIncrement(unit: .pounds)
        #expect(inc.chipLabel(-2.5) == "-2.5")
        #expect(inc.chipLabel(2.5) == "+2.5")
        #expect(inc.chipLabel(5) == "+5")
        #expect(inc.chipLabel(-10) == "-10")
    }

    @Test func kilogramPlateOptionsAndDecimalCrown() {
        let inc = WeightIncrement(unit: .kilograms)
        #expect(inc.plateOptions == [45, 35, 25, 10, 5, 2.5])
        #expect(inc.crownDetent == 0.1)
        #expect(inc.range == 0...300)
    }

    @Test func localeDefaultUS() {
        #expect(WeightIncrement.unitDefault(locale: Locale(identifier: "en_US")) == .pounds)
    }

    @Test func localeDefaultMetric() {
        #expect(WeightIncrement.unitDefault(locale: Locale(identifier: "de_DE")) == .kilograms)
    }

    // MARK: - Context apply

    @Test func contextAppliesUnit() {
        var prefs = WatchSync.Preferences(unit: .kilograms)
        prefs = prefs.applying(context: ["settings.unit": "pounds"])
        #expect(prefs.unit == .pounds)
    }

    @Test func contextAppliesAllSettings() {
        var prefs = WatchSync.Preferences()
        prefs = prefs.applying(context: [
            "settings.unit": "pounds",
            "settings.distanceUnit": "miles",
            "settings.intervalColorBlind": true,
            "settings.restSeconds": 120,
            "settings.warmupMinutes": 4,
            "settings.cooldownMinutes": 3,
            "settings.workoutSounds": false,
        ])
        #expect(prefs.unit == .pounds)
        #expect(prefs.distanceUnit == .miles)
        #expect(prefs.intervalColorBlind)
        #expect(prefs.restSeconds == 120)
        #expect(prefs.warmupMinutes == 4)
        #expect(prefs.cooldownMinutes == 3)
        #expect(!prefs.workoutSounds)
    }

    @Test func contextAppliesSpokenCues() {
        let prefs = WatchSync.Preferences().applying(context: [WatchSync.Key.spokenCues: true])
        #expect(prefs.spokenCues)
    }

    @Test func watchVoiceCueUsesRoundNumbersForWorkIntervals() {
        #expect(WatchVoiceCue.phase(kind: "work", round: 2).speechText == "Round 2")
        #expect(WatchVoiceCue.phase(kind: "rest", round: 2).speechText == "Rest")
    }

    @Test func workoutStartedCueSpeaksTheWorkoutName() {
        #expect(WatchVoiceCue.workoutStarted(title: "HIIT").speechText ==
                       "Workout started. HIIT")
        #expect(WatchVoiceCue.workoutStarted(title: "  ").speechText ==
                       "Workout started")
    }

    @Test func contextAppliesDistanceUnit() {
        var prefs = WatchSync.Preferences(distanceUnit: .kilometers)
        prefs = prefs.applying(context: ["settings.distanceUnit": "miles"])
        #expect(prefs.distanceUnit == .miles)
    }

    @Test func contextAppliesRecentPartners() {
        var prefs = WatchSync.Preferences()
        prefs = prefs.applying(context: [
            "partners.recent": ["Jo", "Sam"],
        ])
        #expect(prefs.recentPartnerNames == ["Jo", "Sam"])
    }

    @Test func contextIgnoresUnknownKeys() {
        var prefs = WatchSync.Preferences(unit: .kilograms)
        prefs = prefs.applying(context: ["unknown": 1])
        #expect(prefs.unit == .kilograms)
    }

    @Test func contextDictRoundTrip() {
        let prefs = WatchSync.Preferences(unit: .pounds, distanceUnit: .miles, intervalColorBlind: true, restSeconds: 60, warmupMinutes: 4, cooldownMinutes: 3, workoutSounds: false, recentPartnerNames: ["Jo"])
        let dict = WatchSync.Preferences.contextDict(prefs)
        let restored = WatchSync.Preferences().applying(context: dict)
        #expect(restored.unit == prefs.unit)
        #expect(restored.distanceUnit == prefs.distanceUnit)
        #expect(restored.intervalColorBlind == prefs.intervalColorBlind)
        #expect(restored.restSeconds == prefs.restSeconds)
        #expect(restored.warmupMinutes == prefs.warmupMinutes)
        #expect(restored.cooldownMinutes == prefs.cooldownMinutes)
        #expect(restored.workoutSounds == prefs.workoutSounds)
        #expect(restored.recentPartnerNames == prefs.recentPartnerNames)
    }

    @Test func contextDictAddsUpdatedAtWhenRequested() {
        let date = Date(timeIntervalSince1970: 1_234)
        let dict = WatchSync.Preferences.contextDict(WatchSync.Preferences(), updatedAt: date)
        #expect(dict[WatchSync.Key.contextUpdatedAt] as? Date == date)
    }

    @Test func customExercisePropertyListRoundTripsSearchFacets() {
        let date = Date(timeIntervalSince1970: 7)
        let exercise = WatchSync.CustomExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
            name: "Cable Y Raise", category: "shoulders", equipment: "cable",
            primaryMuscles: ["deltoids"], secondaryMuscles: ["trapezius"],
            searchKeywords: ["cable", "raise"], isLateral: true, updatedAt: date)
        let restored = WatchSync.CustomExercise(propertyList: exercise.propertyList)
        #expect(restored == exercise)
    }

    @Test func incomingContextParsesPlanAndCustomExercisesForBackgroundApply() {
        let date = Date(timeIntervalSince1970: 9)
        let exercise = WatchSync.CustomExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
            name: "Custom Row", primaryMuscles: ["lats"], updatedAt: date)
        let plan = WatchSync.TodayPlan(
            sessions: [.init(id: "run", kind: .cardio, label: "Run",
                              cardioType: "run", durationMinutes: 20, zone: 2)],
            updatedAt: date)
        var context = WatchSync.Preferences.contextDict(
            WatchSync.Preferences(unit: .pounds), updatedAt: date)
        context.merge(WatchSync.TodayPlan.contextDict(plan)) { _, new in new }
        context[WatchSync.Key.customExercises] = [exercise.propertyList]

        let snapshot = WatchSync.IncomingContext.from(
            context: context,
            applyingTo: WatchSync.Preferences())

        #expect(snapshot.preferences.unit == .pounds)
        #expect(snapshot.todayPlan == plan)
        #expect(snapshot.customExercises == [exercise])
        #expect(snapshot.updatedAt == date)
    }

    @Test func missingKeysPreserveDefaults() {
        var prefs = WatchSync.Preferences(unit: .pounds, restSeconds: 90, warmupMinutes: 2, cooldownMinutes: 4, workoutSounds: false)
        prefs = prefs.applying(context: [:])
        #expect(prefs.unit == .pounds)
        #expect(prefs.restSeconds == 90)
        #expect(prefs.warmupMinutes == 2)
        #expect(prefs.cooldownMinutes == 4)
        #expect(!prefs.workoutSounds)
    }

    @Test func invalidUnitPreservesExisting() {
        var prefs = WatchSync.Preferences(unit: .kilograms)
        prefs = prefs.applying(context: ["settings.unit": "stones"])
        #expect(prefs.unit == .kilograms)
    }

    @Test func invalidDistanceUnitPreservesExisting() {
        var prefs = WatchSync.Preferences(distanceUnit: .kilometers)
        prefs = prefs.applying(context: ["settings.distanceUnit": "parsecs"])
        #expect(prefs.distanceUnit == .kilometers)
    }

    @Test func missingDistanceUnitPreservesDefaults() {
        var prefs = WatchSync.Preferences(distanceUnit: .miles)
        prefs = prefs.applying(context: [:])
        #expect(prefs.distanceUnit == .miles)
    }

    @Test func invalidValuesPreserveExisting() {
        var prefs = WatchSync.Preferences(restSeconds: 90, warmupMinutes: 5, cooldownMinutes: 5, workoutSounds: true)
        prefs = prefs.applying(context: [
            "settings.restSeconds": "fast",
            "settings.warmupMinutes": "long",
            "settings.cooldownMinutes": false,
            "settings.workoutSounds": "yes",
        ])
        #expect(prefs.restSeconds == 90)
        #expect(prefs.warmupMinutes == 5)
        #expect(prefs.cooldownMinutes == 5)
        #expect(prefs.workoutSounds)
    }

    @Test func statusHelpers() {
        let date = Date(timeIntervalSince1970: 1_234)
        #expect(WatchSync.Status.syncing(date).isInProgress)
        #expect(!WatchSync.Status.synced(date).isInProgress)
        #expect(WatchSync.Status.synced(date).toastText == "Watch synced")
        #expect(WatchSync.requestSettingsSyncMessage()[WatchSync.Key.command] as? String == WatchSync.Key.requestSettingsSync)
    }

    @Test func todayPlanContextRoundTripStrengthAndCardio() {
        let updatedAt = Date(timeIntervalSince1970: 42)
        let plan = WatchSync.TodayPlan(sessions: [
            .init(id: "strength", kind: .strength, label: "Strength",
                  exerciseNames: ["Bench Press", "Back Squat"], repLadder: [12, 10, 8]),
            .init(id: "cardio", kind: .cardio, label: "Moderate aerobic",
                  cardioType: "run", durationMinutes: 30, zone: 2),
        ], updatedAt: updatedAt)

        let dict = WatchSync.TodayPlan.contextDict(plan)
        let restored = WatchSync.TodayPlan.from(context: dict)

        #expect(restored == plan)
        #expect(restored?.strengthSessions.first?.exerciseNames == ["Bench Press", "Back Squat"])
        #expect(!(restored?.isRestDay ?? true))
    }

    @Test func versionedPlanPayloadRoundTripsRichStrengthAndCardioAndIgnoresUnknownKeys() {
        let prescription = PlannedExercisePrescription(
            sourceItemID: UUID(uuidString: "00000000-0000-0000-0000-000000000101"),
            exerciseKey: "bench_press",
            exerciseName: "Bench Press",
            sets: [PlannedSetPrescription(
                sourceSetID: UUID(uuidString: "00000000-0000-0000-0000-000000000102"),
                targetReps: 5, targetWeightKg: 80, targetLoadMode: "absolute",
                oneRepMaxPercent: nil, targetRPE: 8, restSeconds: 150)])
        let payload = WatchPlanPayload(
            planSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000103"),
            title: "Upper",
            strength: .init(
                exerciseNames: ["Bench Press"], repLadder: [5],
                prescriptions: [prescription]),
            cardio: [.init(kind: "run", durationSeconds: 1_800, targetZone: 2,
                           intervalPlanData: Data([1, 2, 3]))])

        var propertyList = payload.propertyList
        propertyList["futureField"] = ["ignored": true]
        let restored = WatchPlanPayload(propertyList: propertyList)

        #expect(restored == payload)
        #expect(restored?.version == WatchPlanPayload.currentVersion)
        #expect(restored?.strength?.prescriptions.first?.sets.first?.targetRPE == 8)
        #expect(restored?.cardio.first?.targetZone == 2)
    }

    @Test func todayPlanCarriesRichPayloadAlongsideLegacyFields() {
        let payload = WatchPlanPayload(
            title: "Upper",
            strength: .init(exerciseNames: ["Bench Press"], repLadder: [5],
                            prescriptions: [PlannedExercisePrescription(
                                exerciseName: "Bench Press",
                                sets: [.init(targetReps: 5, targetWeightKg: 80)])]))
        let plan = WatchSync.TodayPlan(sessions: [
            .init(id: "strength", kind: .strength, label: "Upper",
                  exerciseNames: ["Bench Press"], repLadder: [5], planPayload: payload)
        ])

        let restored = WatchSync.TodayPlan.from(context: WatchSync.TodayPlan.contextDict(plan))

        #expect(restored?.sessions.first?.planPayload == payload)
        #expect(restored?.sessions.first?.exerciseNames == ["Bench Press"])
        #expect(restored?.sessions.first?.repLadder == [5])
    }

    @Test func todayPlanFromWeeklyRestDay() {
        let day = WeeklyPlan.DayOutline(date: Date(), label: "Rest", sessions: [
            PlannedSession(id: "rest", kind: .rest, label: "Rest", isHard: false, isRest: true)
        ], isToday: true)

        let plan = WatchSync.TodayPlan.from(day: day)

        #expect(plan.isRestDay)
        #expect(plan.sessions.first?.kind == .rest)
    }

    @Test func todayPlanFromWeeklyStrengthUsesExercisePrescription() {
        let exercise = CoachSession.RecommendedExercise(
            name: "Bench Press",
            sets: 3,
            repsLow: 8,
            repsHigh: 12,
            rir: 2,
            repLadder: [12, 10, 8]
        )
        let day = WeeklyPlan.DayOutline(date: Date(), label: "Strength", sessions: [
            PlannedSession(id: "strength", kind: .strength, label: "Strength",
                           isHard: true, isRest: false, exercises: [exercise])
        ], isToday: true)

        let plan = WatchSync.TodayPlan.from(day: day)

        #expect(plan.strengthSessions.first?.exerciseNames == ["Bench Press"])
        #expect(plan.strengthSessions.first?.repLadder == [12, 10, 8])
    }
}
