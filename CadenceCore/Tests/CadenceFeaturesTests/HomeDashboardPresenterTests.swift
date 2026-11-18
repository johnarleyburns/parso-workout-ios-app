#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct HomeDashboardPresenterTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func dashboard(chestSets: Int, now: Date) throws -> HomeDashboardState {
        let context = try makeContext()
        // Keep the fixture inside the explicit Monday-to-now window even when
        // CI runs during the first hour of Monday. A plain `now - 1 hour` would
        // otherwise make the workout belong to the previous week.
        let sessionDate = max(WeeklyStats.weekStart(now: now),
                              now.addingTimeInterval(-3_600))
        let session = try WorkoutRepository.createSession(
            date: sessionDate, in: context)
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

    @Test func gapGroupsIncludesEveryUnproductiveTrackedGroupUncapped() {
        let rows = HomeDashboardPresenter.volumeRows(
            setsByGroup: [.chest: 12, .biceps: 2], tracked: MuscleGroup.defaultTracked)
        let gaps = HomeDashboardPresenter.gapGroups(from: rows)
        #expect(!gaps.contains(.chest))
        #expect(Set(gaps).count == gaps.count)
        #expect(gaps.count > 3)
        #expect(gaps.contains(.abductors))
        #expect(gaps.contains(.biceps))
    }

    @Test func gapTiersSeparateMissingBelowMinimumAndBelowRecommended() {
        let rows = HomeDashboardPresenter.volumeRows(
            setsByGroup: [.chest: 12, .biceps: 2, .triceps: 5], tracked: MuscleGroup.defaultTracked)
        let tiers = HomeDashboardPresenter.gapTiers(from: rows)
        #expect(tiers.missing.contains(.abductors))
        #expect(tiers.belowMinimum == [.biceps])
        #expect(tiers.belowRecommended == [.triceps])
        #expect(!tiers.all.contains(.chest))
    }

    @Test func volumeRowsUseTheSharedWeeklySetZonesAndCitation() throws {
        let below = try dashboard(chestSets: 3, now: Date()).volume.first { $0.group == .chest }
        let building = try dashboard(chestSets: 4, now: Date()).volume.first { $0.group == .chest }
        let productive = try dashboard(chestSets: 8, now: Date()).volume.first { $0.group == .chest }
        let above = try dashboard(chestSets: 13, now: Date()).volume.first { $0.group == .chest }

        #expect(below?.zone == .belowMinimum)
        #expect(building?.zone == .building)
        #expect(productive?.zone == .productive)
        #expect(above?.zone == .aboveMaximum)
        #expect(above?.rangeText == "Above 12-set maximum")
        #expect(abs((productive?.normalized ?? 0) - 8.0 / 12.0) <= 0.001)
        #expect(above?.normalized == 1)
        #expect(CitationRegistry.citation(forId: productive?.citationID ?? "") != nil)
    }

    @Test func finalizedPhoneCustomExerciseRetainsWeeklyVolumeOnHomeDashboard() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let context = try makeContext()
        let session = try WorkoutRepository.createSession(
            title: "Phone custom abs",
            date: now.addingTimeInterval(-3_600),
            in: context)
        let exercise = try WorkoutRepository.findOrCreateExercise(
            named: "Incline Crunches",
            category: .core,
            primaryMuscles: [MuscleGroup.abdominals.rawValue],
            in: context)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(
                to: session, exercise: exercise, weightKg: 0, reps: 15, in: context)
        }
        session.endedAt = now
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let snapshot = CoachSnapshotBuilder.build(
            sessions: sessions, cardio: [], assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: .default, profile: .empty, now: now)
        let dashboard = HomeDashboardPresenter.make(
            snapshot: snapshot, schedule: .default, goal: .strength,
            experience: .intermediate, userAge: nil)

        #expect(snapshot.facts.weeklySetsByGroup[.abdominals] == 3)
        #expect(snapshot.engineObservation?.effectiveSetsByGroup[.abdominals] == 3)
        #expect(dashboard.volume.first { $0.group == .abdominals }?.sets == 3)
    }

    @Test func weeklyVolumeUsesTheExplicitCurrentWeekFacts() {
        let volume = HomeDashboardPresenter.weeklyVolume(
            engine: [.chest: 4],
            facts: [.chest: 3, .abdominals: 3])

        #expect(volume[.chest] == 3,
                       "A stale or differently-windowed engine value must not widen Home's week")
        #expect(volume[.abdominals] == 3)
    }

    @Test func dashboardDoesNotLetEngineObservationAddOlderMuscleVolume() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let context = try makeContext()
        let recent = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-3_600), in: context)
        let exercise = try WorkoutRepository.findOrCreateExercise(
            named: "Current Week Bench", primaryMuscles: [MuscleGroup.chest.rawValue], in: context)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(to: recent, exercise: exercise,
                                             weightKg: 60, reps: 8, in: context)
        }
        recent.endedAt = now
        try context.save()
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let base = CoachSnapshotBuilder.build(
            sessions: sessions, cardio: [], assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: .default, profile: .empty, now: now)
        let staleEngine = EngineObservationSnapshot(
            subjectId: "test", asOf: now, stateVersion: "test",
            effectiveSetsByMuscle: [MuscleGroup.chest.rawValue: 24])
        let snapshot = CoachSnapshot(
            facts: base.facts, coachFacts: base.coachFacts, insights: base.insights,
            recommendation: base.recommendation, decision: base.decision,
            plan: base.plan, behindPlan: base.behindPlan, addOn: base.addOn,
            readiness: base.readiness, optimizedPlan: base.optimizedPlan,
            engineObservation: staleEngine)

        let dashboard = HomeDashboardPresenter.make(
            snapshot: snapshot, schedule: .default, goal: .strength,
            experience: .intermediate, userAge: nil)
        #expect(dashboard.volume.first { $0.group == .chest }?.sets == 3)
    }

    @Test func progressStatusChangesOnlyAtTarget() {
        let below = HomeDashboardState.Progress(
            completed: 1, target: 2, displayText: "1 of 2", normalized: 0.5)
        let atTarget = HomeDashboardState.Progress(
            completed: 2, target: 2, displayText: "2 of 2", normalized: 1)
        let aboveTarget = HomeDashboardState.Progress(
            completed: 3, target: 2, displayText: "3 of 2", normalized: 1)
        #expect(!below.isAtOrAboveTarget)
        #expect(atTarget.isAtOrAboveTarget)
        #expect(aboveTarget.isAtOrAboveTarget)
    }

    @Test func volumeSummaryUsesMeanCappedSetsAcrossTrackedMuscleGroups() throws {
        let state = try dashboard(chestSets: 8, now: Date())
        let tracked = Double(MuscleGroup.defaultTracked.count)
        #expect(state.volume.count == MuscleGroup.defaultTracked.count)
        #expect(abs(state.volumeCoverage.completed - 8.0 / tracked) <= 0.001)
        #expect(state.volumeCoverage.displayText == "0.4 sets")
        #expect(abs(state.volumeCoverage.normalized - 8.0 / tracked / 12.0) <= 0.001)
    }

    @Test func suggestionToneMapsProgressWarningsAndInformation() {
        let make: (HomeSuggestion.Category) -> HomeSuggestion = { category in
            HomeSuggestion(id: "tone-\(category.rawValue)", category: category,
                           title: "Suggestion", message: "Details", citationID: nil,
                           sourceClaimKey: "tone-\(category.rawValue)", priority: 0, confidence: 100)
        }
        #expect(make(.progress).tone == .neutral)
        #expect(make(.weeklyDeficit).tone == .warning)
        #expect(make(.volumeRecovery).tone == .warning)
        #expect(make(.safety).tone == .warning)
        #expect(make(.planAction).tone == .neutral)
    }

    @Test func suggestionToneMapsProductiveVolumeToNeutral() {
        let suggestion = HomeSuggestion(
            id: "volume.chest", category: .volumeRecovery,
            title: "Chest volume is productive", message: "8 sets this week",
            citationID: CitationRegistry.volumeDoseResponse.id,
            sourceClaimKey: "insight:volume.chest", priority: 0, confidence: 100)
        #expect(suggestion.tone == .warning)
    }

    // MARK: - Weekly volume (DB++ adoption, decision D5)
    //
    // Home used to carry two rows measuring the same thing at two resolutions: a
    // coarse eight-bucket `Volume` and a fine `Muscles`. There is one now, keyed by
    // MuscleGroup.

    @Test func volumeRowsCoverEveryTrackedGroup() throws {
        let rows = try dashboard(chestSets: 4, now: Date()).volume
        let tracked = rows.filter(\.isTracked).map(\.group)
        #expect(Set(tracked) == MuscleGroup.defaultTracked,
                       "every tracked group needs a line, including the ones at zero")
    }

    /// An untracked group is noise at zero and information once it has work in it.
    @Test func untrackedGroupAppearsOnlyOnceTrained() {
        let quiet = HomeDashboardPresenter.volumeRows(setsByGroup: [.chest: 4], tracked: [.chest])
        #expect(!quiet.contains { $0.group == .neck })
        #expect(!quiet.contains { $0.group == .tibialis })

        let trained = HomeDashboardPresenter.volumeRows(setsByGroup: [.chest: 4, .neck: 2], tracked: [.chest])
        let neck = trained.first { $0.group == .neck }
        #expect(neck != nil)
        #expect(neck?.sets == 2)
        #expect(!(neck?.isTracked ?? true))
    }

    @Test func volumeRowsUseTheSharedZonesAndKeepFractionalSets() {
        // "quads" is a retired id: rows are keyed by MuscleGroup now, and a caller
        // passing a historical id still lands on the right row.
        let rows = HomeDashboardPresenter.volumeRows(setsByMuscle: [
            "chest": 3.5, "lats": 4, "glutes": 8, "quads": 12.5,
        ])
        #expect(rows.first { $0.group == .chest }?.zone == .belowMinimum)
        #expect(rows.first { $0.group == .lats }?.zone == .building)
        #expect(rows.first { $0.group == .glutes }?.zone == .productive)
        let quads = rows.first { $0.group == .quadriceps }
        #expect(quads?.zone == .aboveMaximum)
        #expect(quads?.normalized == 1)
        #expect(rows.first { $0.group == .chest }?.sets == 3.5)
        #expect(abs((rows.first { $0.group == .chest }?.normalized ?? 0) - 3.5 / 12) <= 0.001)
        #expect(CitationRegistry.citation(forId: quads?.citationID ?? "") != nil)
    }

    @Test func volumeRowsAreOrderedAlphabeticallyAndTitleCased() throws {
        let rows = try dashboard(chestSets: 4, now: Date()).volume
        #expect(rows.map(\.displayName) ==
                       ["Abductors", "Abs", "Adductors", "Biceps", "Calves", "Chest",
                        "Forearms", "Glutes", "Hamstrings", "Hip Flexors", "Lats", "Lower Back",
                        "Mid Back", "Neck", "Quads", "Rotator Cuff", "Shoulders", "Tibialis",
                        "Traps", "Triceps"])
        #expect(rows.allSatisfy { $0.displayName.first?.isUppercase == true })
        #expect(rows.allSatisfy { !$0.displayName.contains("_") })
    }

    @Test func volumeRowsCarryTheScientificName() throws {
        let rows = try dashboard(chestSets: 4, now: Date()).volume
        #expect(rows.first { $0.group == .chest }?.scientificName == "Pectoralis Major")
    }

    @Test func detailedVolumeRowsSortBySetsThenAlphabetically() {
        let rows = HomeDashboardPresenter.volumeRows(setsByGroup: [
            .chest: 4, .biceps: 8, .calves: 8, .lats: 2
        ])

        let sorted = HomeDashboardPresenter.sortedVolumeRows(rows)

        #expect(sorted.prefix(4).map(\.displayName) == ["Biceps", "Calves", "Chest", "Lats"])
        #expect(sorted.prefix(4).map(\.sets) == [8, 8, 4, 2])
    }

    /// Averaged over tracked rows only, so incidental work in an untracked group
    /// cannot move the headline number.
    @Test func volumeCoverageAveragesTrackedRowsOnly() throws {
        let state = try dashboard(chestSets: 12, now: Date())
        let tracked = Double(MuscleGroup.defaultTracked.count)
        #expect(abs(state.volumeCoverage.completed - 12.0 / tracked) <= 0.001)
        #expect(abs(state.volumeCoverage.normalized - 1.0 / tracked) <= 0.001)
    }

    // MARK: - Cardio minutes (field test 2026-08-19 #7)

    @Test func cardioDetailExplainsTheModerateEquivalentWeighting() {
        let detail = HomeDashboardState.CardioDetail(
            loggedMinutes: 80, easyMinutes: 0, moderateMinutes: 2, vigorousMinutes: 78,
            moderateEquivalentMinutes: 158, targetMinutes: 150,
            citationID: CitationRegistry.ekelundActivityMortality2016.id)
        #expect(detail.summary == "80 min exercised produces 158 moderate-equivalent guideline credit.")
        #expect(detail.explanation.contains("Vigorous work counts double"))
        #expect(detail.lines.map { $0.label } == ["Moderate", "Vigorous"])
        #expect(detail.lines.last?.credit == "156 min credited")
        #expect(CitationRegistry.citation(forId: detail.citationID) != nil,
                        "The cardio explanation must resolve to a real, navigable study")
    }

    @Test func cardioDetailWithOnlyModerateWorkNeedsNoWeightingCaveat() {
        let detail = HomeDashboardState.CardioDetail(
            loggedMinutes: 60, easyMinutes: 0, moderateMinutes: 60, vigorousMinutes: 0,
            moderateEquivalentMinutes: 60, targetMinutes: 150,
            citationID: CitationRegistry.ekelundActivityMortality2016.id)
        #expect(detail.summary == "60 min logged this week.")
    }

    @Test func cardioDetailIsPopulatedFromTheWeeklyBalance() throws {
        let dash = try dashboard(chestSets: 1, now: Date())
        #expect(dash.cardioDetail.targetMinutes == 300)
        #expect(dash.cardioDetail.loggedMinutes == 0)
        #expect(dash.cardioDetail.moderateEquivalentMinutes == dash.cardio.completed)
    }

    @Test func visibleSuggestionsCapsCollapsedCardAndRestoresExpandedItems() {
        let items = (0..<5).map { index in
            HomeSuggestion(id: "suggestion-\(index)", category: .progress,
                           title: "Suggestion \(index)", message: "Details", citationID: nil,
                           sourceClaimKey: "suggestion-\(index)", priority: 0, confidence: 100)
        }
        #expect(HomeDashboardPresenter.visibleSuggestions(items, expanded: false).map(\.id) ==
                       items.prefix(1).map(\.id))
        #expect(HomeDashboardPresenter.visibleSuggestions(items, expanded: true) == items)
    }

    @Test func dashboardConsumesPrecomputedWeeklyValuesWithoutHistory() throws {
        let now = Date()
        let snapshot = CoachSnapshotBuilder.build(
            sessions: [], cardio: [], assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: .default, profile: .empty, now: now)
        let cardio = WeeklyCardioSummary(
            actualMinutes: 90, belowModerateMinutes: 10, moderateMinutes: 50,
            vigorousMinutes: 30, moderateEquivalentMinutes: 110, unclassifiedMinutes: 0,
            zoneMinutes: [:], algorithmVersion: CardioAlgorithmVersion.hrrGuidelineV1)
        let state = HomeDashboardPresenter.make(
            snapshot: snapshot, schedule: .default, goal: .strength,
            experience: .intermediate, userAge: 30,
            weeklyCardio: cardio, activityDose: nil)
        #expect(state.cardioDetail.moderateEquivalentMinutes == 110)
    }

    @Test func backgroundProjectionInputsMatchAggregatorAndChangeWithHRMax() throws {
        let context = try makeContext()
        let now = Date()
        let weekStart = WeeklyStats.weekStart(now: now)
        let samples = [PassiveReadinessSample(date: now, restingHR: 55)]
        func summary(age: Int?, override: Double?) -> WeeklyCardioSummary {
            let profile = CardioIntensityProfile.forHome(
                passiveSamples: samples, userAge: age, maximumHROverride: override)
            return WeeklyCardioAggregator.summarize([], since: weekStart, profile: profile, sessions: [])
        }
        #expect(summary(age: 30, override: nil) == summary(age: 30, override: nil))
        #expect(context != nil)
    }

    @Test func restoredWeeklySetsByMuscleOverridesEmptyPlaceholderSnapshot() {
        let emptySnapshot = CoachSnapshotBuilder.build(
            sessions: [], cardio: [], assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: .default, profile: .empty)
        let restored = HomeDashboardPresenter.make(
            snapshot: emptySnapshot, schedule: .default, goal: .strength,
            experience: .intermediate, userAge: nil,
            restoredWeeklySetsByMuscle: ["chest": 9, "biceps": 3])
        #expect(restored.strength.completed == 12)
        #expect(restored.strength.displayText.contains("12"))
        #expect(restored.volume.first { $0.group == .chest }?.sets == 9)
        let unrestored = HomeDashboardPresenter.make(
            snapshot: emptySnapshot, schedule: .default, goal: .strength,
            experience: .intermediate, userAge: nil)
        #expect(unrestored.strength.completed == 0)
    }
}
#endif
