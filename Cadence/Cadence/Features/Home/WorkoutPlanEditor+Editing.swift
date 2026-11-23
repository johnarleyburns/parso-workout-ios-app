import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

extension WorkoutPlanEditor {
    /// A generated Personalized plan carries goal-range reps and set count but
    /// no loads. Seed both the reps and loads from the owner's own last workout
    /// so the preview shows what they actually did. Explicit plan loads and
    /// bodyweight movements are preserved.
    func seedSuggestedOwnerDefaults() {
        guard let historyIndex else { return }
        for index in plan.exercises.indices {
            let name = plan.exercises[index].name
            let history = historyIndex.history(forExerciseNamed: name,
                                                performerID: nil, people: allPeople)
            plan.exercises[index].sets = PartnerPlanResolver.suggestedOwnerSets(
                plan.exercises[index].sets, history: history)
            if history.hasRepHistory { seededHistoryNames.insert(name) }
        }
    }

    /// The catalog and CloudKit history can arrive after this sheet appears.
    /// Retry only movements that had no history the first time, so a late
    /// imported exercise gets the same reps/loads the live session would use.
    func seedMissingSuggestedHistory() {
        guard suggestedStrength != nil || plan.suggestedWorkoutStyle != nil,
              let historyIndex else { return }
        for index in plan.exercises.indices {
            let name = plan.exercises[index].name
            guard !seededHistoryNames.contains(name) else { continue }
            let history = historyIndex.history(forExerciseNamed: name,
                                                performerID: nil, people: allPeople)
            guard history.hasRepHistory else { continue }
            plan.exercises[index].sets = PartnerPlanResolver.suggestedOwnerSets(
                plan.exercises[index].sets, history: history,
                updateRepsWhenLoadPresent: true)
            seededHistoryNames.insert(name)
        }
    }

    /// Rebuilds the history snapshot and fills anything that was unavailable
    /// when the plan first opened. Never overwrites a load the user already has.
    func refreshPlanHistory() {
        exerciseIndex = Dictionary(allExercises.map { ($0.name.lowercased(), $0) },
                                   uniquingKeysWith: { first, _ in first })
        historyIndex = WorkoutPlanPartnerHistory.Index(context: modelContext)
        seedMissingSuggestedHistory()
        seedPlanWeights()
        resolvePartnerPlans()
        // Partner plans are rebuilt from their own set ladders; fill any loads
        // those rows still leave blank from the same full sample history.
        seedPlanWeights()
        refreshPlanVolume()
    }

    /// Every planned working set gets a load before the workout starts, using
    /// the same exact-rep / inverse-e1RM / last-weight cascade as set entry.
    /// Explicit loads and percentage/bodyweight modes are never overwritten.
    func seedPlanWeights() {
        guard let historyIndex, !plan.exercises.isEmpty else { return }
        plan = PlanWeightSeeder.fill(plan: plan, formula: settings.formula) { name, performerID in
            historyIndex.history(forExerciseNamed: name, performerID: performerID, people: allPeople)
        }
    }

    /// Fills every partner's plan from *their* history for the owner's
    /// exercises. Runs on appear, roster changes, and after exercise changes.
    func resolvePartnerPlans() {
        let roster = rosterMembers()
        guard !plan.exercises.isEmpty else { return }
        let index: WorkoutPlanPartnerHistory.Index
        if let historyIndex {
            index = historyIndex
        } else {
            index = WorkoutPlanPartnerHistory.Index(context: modelContext)
            historyIndex = index
        }
        plan = PartnerPlanResolver.fill(plan: plan, roster: roster) { name, performerID in
            index.history(forExerciseNamed: name, performerID: performerID, people: allPeople)
        }
    }

    func rosterMembers() -> [PartnerPlanResolver.RosterMember] {
        let peopleByID = Dictionary(allPeople.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = plan.partnerIDs.compactMap { id -> PartnerPlanResolver.RosterMember? in
            guard let person = peopleByID[id], !person.isArchived else { return nil }
            return PartnerPlanResolver.RosterMember(performerID: person.isMe ? nil : person.id,
                                                    name: person.isMe ? "Me" : person.name)
        }
        let hasPartner = ordered.contains { $0.performerID != nil }
        guard hasPartner else { return [.init(performerID: nil, name: "Me")] }
        if ordered.contains(where: { $0.performerID == nil }) { return ordered }
        return [.init(performerID: nil, name: "Me")] + ordered
    }

    func applyPickedExercise(_ exercise: Exercise, for intent: ExercisePickerIntent) {
        switch intent {
        case .add:
            // A newly added movement follows the plan's shared rep structure,
            // not one historical set (or a lone ×10 placeholder). The weight
            // seeder below fills each set's load from this movement's history.
            let structure = plan.exercises.first(where: { !$0.sets.isEmpty })?
                .sets.map(\.targetReps) ?? []
            let sets = structure.isEmpty
                ? ownerSeedSets(for: exercise.name)
                : WorkoutPlanRepSchemeOptions.templateSets(following: structure)
            plan.exercises.append(EditableExercise(name: exercise.name,
                                                    sets: sets,
                                                    notes: ""))
            // Keep the chosen structure for this new row. Suggested plans must
            // not replace it with a previous session's reps.
            if !structure.isEmpty {
                seededHistoryNames.insert(exercise.name)
            }
        case .swap(let id):
            guard let index = plan.exercises.firstIndex(where: { $0.id == id }) else { return }
            plan.exercises[index].name = exercise.name
            // A swapped movement must not inherit the previous movement's load;
            // re-seed from this exercise's own history.
            plan.exercises[index].sets = plan.exercises[index].sets.map { set in
                guard set.loadMode == .straight else { return set }
                var updated = set
                updated.targetWeight = nil
                return updated
            }
            // The picked movement has its own history; allow the history seed to
            // fill it even if a same-named row was already resolved earlier.
            seededHistoryNames.remove(exercise.name)
        }
        seedMissingSuggestedHistory()
        seedPlanWeights()
        resolvePartnerPlans()
        seedPlanWeights()
    }

    private func ownerSeedSets(for name: String) -> [EditableSet] {
        PartnerPlanResolver.ownerSeedSets(
            history: WorkoutPlanPartnerHistory.history(forExerciseNamed: name,
                                                       performerID: nil,
                                                       people: allPeople,
                                                       context: modelContext),
            defaultReps: 10)
    }
}

extension View {
    /// Home's card treatment so plan editor rows retain the dashboard rhythm.
    func workoutPlanCard() -> some View {
        padding(CGFloat(LayoutMetrics.cardPadding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .green)
    }
}
