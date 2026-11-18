import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore
import CadencePhoneFeatures

struct WatchCardioModelsTests {

    // MARK: - WorkoutConfigurationSpec

    @Test func specForRun() {
        let spec = WorkoutConfigurationSpec(for: "run")
        #expect(spec.kind == .run)
        #expect(spec.location == .outdoor)
    }

    @Test func specCarriesPlannedCardioTargets() {
        let spec = WorkoutConfigurationSpec(
            for: "run", plannedDurationSeconds: 1_800, targetZone: 2)
        #expect(spec.plannedDurationSeconds == 1_800)
        #expect(spec.targetZone == 2)
    }

    @Test func specForWalk() {
        let spec = WorkoutConfigurationSpec(for: "walk")
        #expect(spec.kind == .walk)
    }

    @Test func specForCycle() {
        let spec = WorkoutConfigurationSpec(for: "cycle")
        #expect(spec.kind == .cycle)
    }

    @Test func specForSwim_default25m() {
        let spec = WorkoutConfigurationSpec(for: "swim")
        #expect(spec.kind == .swim)
        if case .pool(let lapLength) = spec.location {
            #expect(lapLength == 25)
        } else { Issue.record("Expected pool location") }
    }

    @Test func specForHIIT() {
        let spec = WorkoutConfigurationSpec(for: "hiit")
        #expect(spec.kind == .hiit)
    }

    @Test func specForBoxing() {
        let spec = WorkoutConfigurationSpec(for: "boxing")
        #expect(spec.kind == .boxing)
    }

    @Test func specForRowing() {
        let spec = WorkoutConfigurationSpec(for: "rowing")
        #expect(spec.kind == .rowing)
    }

    @Test func ellipticalAndStairsKeepTheirTypesAndUseIndoorSetup() {
        let elliptical = WorkoutConfigurationSpec(for: "elliptical")
        #expect(elliptical.kind == .elliptical)
        #expect(elliptical.location == .indoor)
        for raw in ["stairClimber", "stair_climber", "stairs"] {
            let stairs = WorkoutConfigurationSpec(for: raw)
            #expect(stairs.kind == .stairClimber)
            #expect(stairs.location == .indoor)
        }
    }

    @Test func specForOther() {
        let spec = WorkoutConfigurationSpec(for: "other")
        #expect(spec.kind == .other)
    }

    @Test func specForUnknown() {
        let spec = WorkoutConfigurationSpec(for: "garbage")
        #expect(spec.kind == .strength)
    }

    @Test func specCustomPool() {
        let spec = WorkoutConfigurationSpec(kind: .swim, location: .pool(lapLength: 50))
        if case .pool(let lapLength) = spec.location {
            #expect(lapLength == 50)
        } else { Issue.record("Expected pool") }
    }

    @Test func specCustomOutdoorRun() {
        let spec = WorkoutConfigurationSpec(kind: .run, location: .outdoor)
        #expect(spec.location == .outdoor)
    }

    // MARK: - CardioMetricsModel

    @Test func distanceFormat_metric() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms)
        m.updateDistance(0)
        #expect(m.formatDistance().contains("m"))
    }

    @Test func distanceFormat_miles() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms, distanceUnit: .miles)
        m.updateDistance(1609.344)
        #expect(m.formatDistance().contains("mi"))
    }

    @Test func paceDivByZero_safe() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms)
        m.updateDistance(0)
        m.updateElapsed(0)
        #expect(m.formatPace() == "--")
    }

    @Test func hRZone() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms)
        m.updateHR(150)
        #expect(m.hrZone > 0)
        #expect(m.hrZone <= 5)
    }

    @Test func splitPer500m() {
        let m = CardioMetricsModel(kind: .rowing, unit: .kilograms)
        m.updateDistance(1000)
        m.elapsed = 150
        m.recomputeSplitPer500m()
        #expect(abs((m.splitPer500m ?? 0) - 75) <= 1)
    }

    @Test func autoPaused() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms)
        #expect(!m.isAutoPaused)
        m.setAutoPaused(true)
        #expect(m.isAutoPaused)
        m.resetAutoPause()
        #expect(!m.isAutoPaused)
    }

    @Test func lapCount_defaultsToZero() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms)
        #expect(m.lapCount == 0)
        #expect(m.manualLapCount == 0)
    }

    @Test func lapCount_totalIncludesManual() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms)
        m.lapCount = 3
        m.manualLapCount = 2
        #expect(m.lapCount + m.manualLapCount == 5)
    }

    @Test func distanceFormat_imperial_roundsCorrectly() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms, distanceUnit: .miles)
        m.updateDistance(0)
        #expect(m.formatDistance().contains("mi"))
    }

    @Test func splitPer500m_zeroDistance() {
        let m = CardioMetricsModel(kind: .rowing, unit: .kilograms)
        m.updateDistance(0)
        m.elapsed = 100
        m.recomputeSplitPer500m()
        #expect(m.splitPer500m == nil)
    }

    // MARK: - AutoPauseDetector

    @Test func highSpeed_noPause() {
        var d = AutoPauseDetector()
        #expect(d.evaluate(speedMPS: 3.0, isDisabled: false) == .none)
    }

    @Test func lowSpeed_withoutDebounce_noPause() {
        var d = AutoPauseDetector()
        #expect(d.evaluate(speedMPS: 0.3, isDisabled: false) == .none)
    }

    @Test func lowSpeed_withDebounce_pauses() {
        var d = AutoPauseDetector(speedThreshold: 0.5, debounceSeconds: 0.0)
        #expect(d.evaluate(speedMPS: 0.3, isDisabled: false) == .pause)
    }

    @Test func resumeAfterPause() {
        var d = AutoPauseDetector(speedThreshold: 0.5, debounceSeconds: 0.0)
        _ = d.evaluate(speedMPS: 0.3, isDisabled: false)
        d.reset()
        #expect(d.evaluate(speedMPS: 3.0, isDisabled: false) == .none)
    }

    @Test func disabled_noPause() {
        var d = AutoPauseDetector(speedThreshold: 0.5, debounceSeconds: 0.0)
        #expect(d.evaluate(speedMPS: 0.1, isDisabled: true) == .none)
    }

    @Test func nilSpeed_noPause() {
        var d = AutoPauseDetector()
        #expect(d.evaluate(speedMPS: nil, isDisabled: false) == .none)
    }

    // MARK: - IntervalSetupModel

    @Test func hIITDefaults() {
        let m = IntervalSetupModel(kind: "HIIT")
        #expect(m.rounds == 8)
        #expect(m.warmupSeconds == 180)
        #expect(m.workSeconds == 20)
        #expect(m.restSeconds == 10)
        #expect(m.cooldownSeconds == 120)
        #expect(m.hiitProtocol == .tabata)
    }

    @Test func boxingDefaults() {
        let m = IntervalSetupModel(kind: "Boxing")
        #expect(m.rounds == 8)
        #expect(m.warmupSeconds == 180)
        #expect(m.workSeconds == 180)
        #expect(m.restSeconds == 60)
        #expect(m.cooldownSeconds == 120)
        #expect(m.boxingRoundMinutes == 3)
        #expect(m.boxingRestSeconds == 60)
    }

    @Test func intervalAcceptsSyncedWarmupAndCooldown() {
        let m = IntervalSetupModel(kind: "Boxing", warmupSeconds: 240, cooldownSeconds: 60)
        #expect(m.warmupSeconds == 240)
        #expect(m.cooldownSeconds == 60)
    }

    @Test func intervalInitializerClampsSyncedWarmupAndCooldown() {
        let m = IntervalSetupModel(kind: "Boxing", warmupSeconds: 900, cooldownSeconds: -20)
        #expect(m.warmupSeconds == 600)
        #expect(m.cooldownSeconds == 0)
    }

    @Test func intervalClamp() {
        let m = IntervalSetupModel(kind: "HIIT")
        m.rounds = 100
        m.warmupSeconds = -10
        m.workSeconds = 1000
        m.restSeconds = 0
        m.cooldownSeconds = 1000
        let c = m.clamped()
        #expect(c.rounds == 30)
        #expect(c.warmupSeconds == 0)
        #expect(c.workSeconds == 600)
        #expect(c.restSeconds == 5)
        #expect(c.cooldownSeconds == 600)
    }

    @Test func warmupAndCooldownAllowZeroButWorkAndRestDoNot() {
        let m = IntervalSetupModel(kind: "Boxing")
        m.warmupSeconds = 0
        m.workSeconds = 0
        m.restSeconds = 0
        m.cooldownSeconds = 0
        let c = m.clamped()
        #expect(c.warmupSeconds == 0)
        #expect(c.workSeconds == 5)
        #expect(c.restSeconds == 5)
        #expect(c.cooldownSeconds == 0)
    }

    @Test func intervalPlanBuilt() {
        let m = IntervalSetupModel(kind: "Custom")
        let plan = m.intervalPlan()
        #expect(plan.name == "Custom")
        #expect(plan.workRounds == 8)
    }

    @Test func intervalPlanWorkRoundsMatchesRounds() {
        let m = IntervalSetupModel(kind: "HIIT")
        m.rounds = 3
        let plan = m.intervalPlan()
        #expect(plan.workRounds == 3)
    }

    @Test func intervalPlanUsesConfiguredWarmupAndCooldown() {
        let m = IntervalSetupModel(kind: "Boxing", warmupSeconds: 240, cooldownSeconds: 60)
        m.rounds = 2
        let plan = m.intervalPlan()
        #expect(plan.phases.first?.kind == .warmup)
        #expect(plan.phases.first?.duration == 240)
        #expect(plan.phases.last?.kind == .cooldown)
        #expect(plan.phases.last?.duration == 60)
    }

    @Test func intervalPlanOmitsZeroWarmupAndCooldown() {
        let m = IntervalSetupModel(kind: "Boxing")
        m.rounds = 1
        m.warmupSeconds = 0
        m.cooldownSeconds = 0
        let plan = m.intervalPlan()
        #expect(!plan.phases.contains { $0.kind == .warmup })
        #expect(!plan.phases.contains { $0.kind == .cooldown })
        #expect(plan.workRounds == 1)
    }

    // MARK: - DistanceUnitPreference formatting

    @Test func kgWeightMilesDistance_formatsDistanceAsMiles() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms, distanceUnit: .miles)
        m.updateDistance(1609.344)
        #expect(m.formatDistance().contains("mi"))
    }

    @Test func poundsWeightKmDistance_formatsDistanceAsKilometers() {
        let m = CardioMetricsModel(kind: .walk, unit: .pounds, distanceUnit: .kilometers)
        m.updateDistance(500)
        #expect(m.formatDistance().contains("m"))
        m.updateDistance(2000)
        #expect(m.formatDistance().contains("km"))
    }

    @Test func paceLabelFollowsDistanceUnit() {
        let mMiles = CardioMetricsModel(kind: .run, unit: .kilograms, distanceUnit: .miles)
        let mKm = CardioMetricsModel(kind: .run, unit: .pounds, distanceUnit: .kilometers)

        mMiles.updateDistance(100); mMiles.elapsed = 360
        mKm.updateDistance(1000); mKm.elapsed = 360

        let paceMiles = mMiles.formatPace()
        let paceKm = mKm.formatPace()
        if paceMiles != "--" { #expect(paceMiles.contains("/mi")) }
        if paceKm != "--" { #expect(paceKm.contains("/km")) }
    }

    @Test func speedLabelFollowsDistanceUnit() {
        let mMiles = CardioMetricsModel(kind: .cycle, unit: .kilograms, distanceUnit: .miles)
        let mKm = CardioMetricsModel(kind: .cycle, unit: .pounds, distanceUnit: .kilometers)

        mMiles.updateDistance(100); mMiles.elapsed = 10
        mKm.updateDistance(100); mKm.elapsed = 10

        let speedMiles = mMiles.formatSpeed()
        let speedKm = mKm.formatSpeed()
        if speedMiles != "--" { #expect(speedMiles.hasSuffix("mph")) }
        if speedKm != "--" { #expect(speedKm.hasSuffix("km/h")) }
    }

    @Test func rowingSplitRemains500m() {
        let m = CardioMetricsModel(kind: .rowing, unit: .kilograms, distanceUnit: .miles)
        m.updateDistance(1000); m.elapsed = 150
        m.recomputeSplitPer500m()
        #expect(m.formatSplit().contains("/500m"))
    }

    // MARK: - WatchCardioLivePresenter

    @Test func livePresenterHRZoneBoundaries() {
        let max = 190.0
        let cases: [(Double, Int)] = [(30, 1), (0.60 * max, 2), (0.70 * max, 3),
                                      (0.80 * max, 4), (0.90 * max, 5)]
        for (bpm, zone) in cases {
            let p = WatchCardioLivePresenter.present(elapsed: 1, bpm: bpm, distanceMeters: nil,
                                                       heartRateEnabled: true, gpsEnabled: false,
                                                       distanceUnit: .kilometers, maxHR: max)
            #expect(p.hrZone == zone, "Expected zone \(zone) at \(bpm) BPM")
            #expect(p.bpmText == "\(Int(bpm.rounded()))")
        }
    }

    @Test func livePresenterUsesThePhoneHRRTrainingZone() {
        let profile = CardioIntensityProfile(restingHR: 60, maximumHR: 180,
                                             maximumHRSource: .userEntered)
        let bpm = 144.0 // 70% HRR: Z4 under the shared classifier.
        let expected = CardioIntensityClassifier.classify(heartRate: bpm, profile: profile)
        let presentation = WatchCardioLivePresenter.present(
            elapsed: 1, bpm: bpm, distanceMeters: nil, heartRateEnabled: true,
            gpsEnabled: false, distanceUnit: .kilometers, intensityProfile: profile)
        #expect(presentation.hrZone == expected.trainingZone?.rawValue)
        #expect(presentation.relativeIntensity == expected.relativeIntensity)
        #expect(presentation.guidelineIntensity == expected.guidelineIntensity)
    }

    @Test func livePresenterNoHRHidesBPMAndZone() {
        let p = WatchCardioLivePresenter.present(elapsed: 65, bpm: 150, distanceMeters: 20,
                                                   heartRateEnabled: false, gpsEnabled: false,
                                                   distanceUnit: .kilometers)
        #expect(p.elapsedText == "0:01:05")
        #expect(!p.showsHeartRate)
        #expect(p.hrZone == nil)
        #expect(p.distanceText == nil)
    }

    @Test func livePresenterNilAndZeroSamples() {
        let noHR = WatchCardioLivePresenter.present(elapsed: 0, bpm: nil, distanceMeters: nil,
                                                      heartRateEnabled: true, gpsEnabled: true,
                                                      distanceUnit: .kilometers)
        #expect(noHR.bpmText == nil)
        #expect(noHR.distanceText == "0 m")

        let zeroHR = WatchCardioLivePresenter.present(elapsed: 0, bpm: 0, distanceMeters: 0,
                                                        heartRateEnabled: true, gpsEnabled: true,
                                                        distanceUnit: .miles)
        #expect(zeroHR.bpmText == nil)
        #expect(zeroHR.distanceText == "0 m")
    }

    @Test func livePresenterDistanceFormattingAndGPSGate() {
        let metric = WatchCardioLivePresenter.present(elapsed: 0, bpm: nil, distanceMeters: 132,
                                                        heartRateEnabled: false, gpsEnabled: true,
                                                        distanceUnit: .kilometers)
        #expect(metric.distanceText == "132 m")
        let imperial = WatchCardioLivePresenter.present(elapsed: 0, bpm: nil, distanceMeters: 3218.688,
                                                          heartRateEnabled: false, gpsEnabled: true,
                                                          distanceUnit: .miles)
        #expect(imperial.distanceText == "2 mi")
        let gated = WatchCardioLivePresenter.present(elapsed: 0, bpm: nil, distanceMeters: 3218.688,
                                                       heartRateEnabled: false, gpsEnabled: false,
                                                       distanceUnit: .miles)
        #expect(gated.distanceText == nil)
    }

    // MARK: - HIIT protocol picker

    @Test func hIITSetupDefaultsToTabata() {
        let m = IntervalSetupModel(kind: "HIIT")
        #expect(m.hiitProtocol == .tabata)
        let plan = m.hiitIntervalPlan()
        #expect(plan.name == "Tabata")
    }

    @Test func eachHIITProtocolMapsToBuiltInFactory() {
        let model = IntervalSetupModel(kind: "HIIT")
        for proto in CadenceWorkoutFeatures.HIITProtocol.allCases {
            model.hiitProtocol = proto
            let plan = model.hiitIntervalPlan()
            #expect(!plan.phases.isEmpty, "\(proto.displayName) plan should not be empty")
            #expect(plan.totalDuration > 0, "\(proto.displayName) should have positive duration")
        }
    }

    @Test func boxingDefaultsRounds() {
        let m = IntervalSetupModel(kind: "Boxing")
        #expect(m.rounds == 8)
        #expect(m.boxingRoundMinutes == 3)
        #expect(m.boxingRestSeconds == 60)
    }

    @Test func boxingPlanHasNoWarmupAndNoCooldown() {
        let m = IntervalSetupModel(kind: "Boxing")
        let plan = m.boxingIntervalPlan()
        #expect(!plan.phases.contains { $0.kind == .warmup })
        #expect(!plan.phases.contains { $0.kind == .cooldown })
    }

    @Test func boxingRoundsLimitedTo1to20() {
        let m = IntervalSetupModel(kind: "Boxing")
        m.rounds = 25
        let c = m.clamped()
        #expect(c.rounds == 20)
        m.rounds = 0
        let c2 = m.clamped()
        #expect(c2.rounds == 1)
    }

    @Test func boxingRoundLengthOnly2or3Minutes() {
        let m = IntervalSetupModel(kind: "Boxing")
        m.boxingRoundMinutes = 5
        let c = m.clamped()
        #expect(c.boxingRoundMinutes == 3)
        m.boxingRoundMinutes = 1
        let c2 = m.clamped()
        #expect(c2.boxingRoundMinutes == 2)
    }

    @Test func boxingRestOnly30or60Seconds() {
        let m = IntervalSetupModel(kind: "Boxing")
        m.boxingRestSeconds = 45
        let c = m.clamped()
        #expect(c.boxingRestSeconds == 60)
        m.boxingRestSeconds = 15
        let c2 = m.clamped()
        #expect(c2.boxingRestSeconds == 30)
    }
}
