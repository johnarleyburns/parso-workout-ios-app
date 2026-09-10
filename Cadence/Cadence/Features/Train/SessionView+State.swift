import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension SessionView {
    func isBodyweight(_ exercise: Exercise) -> Bool {
        SessionViewModel.isBodyweight(exercise)
    }

    var plannedOnlyNames: [String] {
        SessionViewModel.plannedOnlyNames(session: session)
    }
    /// Resolves the planned-only movements to their catalog rows once per
    /// structural change instead of once per redraw.
    func indexedPlannedExercises() -> [String: Exercise] {
        let names = SessionViewModel.plannedOnlyNames(session: session)
        guard !names.isEmpty else { return [:] }
        var index: [String: Exercise] = [:]
        for name in names {
            if let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) {
                index[name] = ex
            }
        }
        return index
    }
    var isEmptySession: Bool {
        SessionViewModel.isEmptySession(session: session)
    }
    var plan: WorkoutPlan? {
        session.planKey.flatMap { PlanCatalog.plan(forKey: $0) }
    }
    func prescription(for name: String) -> String? {
        SessionViewModel.prescription(for: name, session: session, plan: plan, unit: settings.unit)
    }

    func isPrescribedMovement(_ name: String) -> Bool {
        SessionViewModel.isPrescribedMovement(name, session: session)
    }

    func openInlineEditor(for exercise: Exercise, editingSetID: UUID? = nil,
                                  repsOverride: Int? = nil, performerID: UUID? = nil) {
        inlineExerciseID = exercise.id
        inlineExercise = exercise
        inlineEditingSetID = editingSetID
        setEditorIdentity = editingSetID ?? UUID()
        pendingRepsOverride = repsOverride
        pendingPerformerID = performerID
        pendingPerformerWasProvided = performerID != nil || repsOverride != nil
        setEditorRoute = editingSetID.map { .edit(exerciseID: exercise.id, setID: $0) } ?? .add(exerciseID: exercise.id)
        if !dumbbellInfoShown, case .dumbbell = exercise.equipmentValue {
            dumbbellInfoShown = true
            showDumbbellInfo = true
        }
        if !kettlebellInfoShown, case .kettlebell = exercise.equipmentValue {
            kettlebellInfoShown = true
            showKettlebellInfo = true
        }
        recordActivity()
    }
    func inlineEditorConfig() -> InlineEditorConfig? {
        guard inlineExerciseID != nil, let exercise = inlineExercise else { return nil }
        let isEditing = inlineEditingSetID != nil
        let editingSet = isEditing ? session.orderedSets.first(where: { $0.id == inlineEditingSetID }) : nil
        if isEditing, editingSet == nil { return nil }
        let performerID: UUID? = isEditing
            ? (editingSet?.performedBy?.isMe ?? true ? nil : editingSet?.performedBy?.id)
            : (pendingPerformerWasProvided
                ? pendingPerformerID
                : nextPerson(for: exercise).flatMap { $0.isMe ? nil : $0.id })

        let defaults = performerDefaults(for: exercise)
        let own = defaults.first { $0.performerID == performerID }
        let weight: String
        let hint: Double?
        if isEditing, let set = editingSet {
            weight = Format.weightValue(set.weight, unit: settings.unit)
            hint = nil
        } else if let own, !own.weight.isEmpty {
            weight = own.weight
            hint = own.weightKg
        } else {
            // A coach load belongs to Me. A partner with no resolved load must
            // open at zero rather than silently inheriting the owner's weight.
            let prescribedKg = performerID == nil && isPrescribedMovement(exercise.name)
                ? session.prescribedLoadKg : 0
            weight = prescribedKg > 0 ? Format.weightValue(prescribedKg, unit: settings.unit) : ""
            hint = nil
        }
        let reps: Int
        if isEditing, let set = editingSet {
            reps = set.reps
        } else {
            reps = pendingRepsOverride ?? own?.reps ?? PerformerSetPlanner.defaultReps
        }
        let rpe: Int? = isEditing ? editingSet?.rpe.map { Int($0.rounded()) } : nil
        let bodyweight = isEditing ? (editingSet?.usesBodyweight ?? false) : isBodyweight(exercise)
        let workingSets = session.orderedSets.filter { $0.exercise?.id == exercise.id && !$0.isWarmup }
        let number = isEditing ? (workingSets.firstIndex(where: { $0.id == editingSet?.id }).map { $0 + 1 } ?? workingSets.count + 1) : workingSets.count + 1
        return InlineEditorConfig(
            id: isEditing ? (editingSet?.id ?? setEditorIdentity) : setEditorIdentity,
            isEditing: isEditing,
            weight: weight,
            reps: reps,
            rpe: rpe,
            bodyweight: bodyweight,
            performerID: performerID,
            roster: rosterEntries,
            hasPartners: hasPartners,
            unit: settings.unit,
            priorWeightHint: hint,
            performerDefaults: defaults,
            weightSourceText: own?.weightSourceText,
            exerciseName: exercise.name,
            setNumberText: isEditing ? "Editing set \(number)" : "Set \(number) of \(max(number, session.plannedRepLadder.count))",
            recordedText: isEditing ? "Recorded" : nil,
            effortMode: lastEffortMode
        )
    }
    func closeInlineEditor() {
        inlineExerciseID = nil
        inlineExercise = nil
        inlineEditingSetID = nil
        pendingRepsOverride = nil
        pendingPerformerID = nil
        pendingPerformerWasProvided = false
        setEditorRoute = nil
    }
    func recordInlineSet(for exercise: Exercise, draft: SetDraft) {
        let kg = SessionViewModel.canonicalKg(input: draft.weightString, unit: draft.unit,
                                              plateRounding: settings.plateRounding)
        let rpe = draft.rpe.map(Double.init)
        if let editingSetID = inlineEditingSetID,
           let editing = session.orderedSets.first(where: { $0.id == editingSetID }) {
            try? WorkoutRepository.updateSet(editing, weightKg: kg, reps: draft.reps,
                                             rpe: .some(rpe),
                                             usesBodyweight: draft.bodyweight,
                                             performedBy: .some(people(for: draft.performerID)),
                                             in: context)
        } else {
            addSet(to: exercise, weightKg: kg, reps: draft.reps, rpe: rpe, isWarmup: false,
                   usesBodyweight: draft.bodyweight, note: nil, performedBy: people(for: draft.performerID))
        }
        expandedExerciseID = exercise.id
        pendingScrollExerciseID = exercise.id
        closeInlineEditor()
    }
    func deleteInlineSet() {
        guard let setID = inlineEditingSetID,
              let set = session.orderedSets.first(where: { $0.id == setID }) else { return }
        try? WorkoutRepository.deleteSet(set, in: context)
        closeInlineEditor()
    }
    func people(for id: UUID?) -> Person? {
        guard let id else { return nil }
        return allPeople.first { $0.id == id }
    }
    func exerciseForID(_ id: UUID) -> Exercise? {
        session.exercisesInOrder.first { $0.id == id }
    }
    func setPerformedBy(_ set: SetEntry, performerID: UUID?) -> Bool {
        SessionViewModel.setPerformedBy(set, performerID: performerID)
    }
    func setPerformedBy(_ set: SetEntry, person: Person) -> Bool {
        person.isMe ? set.isOwnerSet : (set.performedBy?.id == person.id)
    }
    /// One row per roster member: what THEIR next set on this exercise should be,
    /// plus their own prior-session and this-session history so the editor's
    /// History card re-derives when the selected performer changes (2026-08-19 #2,
    /// 2026-08-20 issue 3).
    func performerDefaults(for exercise: Exercise) -> [InlineEditorConfig.PerformerDefault] {
        let ctx = cache.state.contexts.first { $0.exerciseID == exercise.id }
        return rosterEntries.map { entry in
            let performerID = entry.isMe ? nil : entry.personID
            let logged = loggedReps(for: exercise, performerID: performerID)
            let resolved = resolvedSet(for: exercise, setIndex: logged.count, performerID: performerID)
            let weightKg = resolved.weightKg.map {
                SessionViewModel.roundedInferredWeightKg($0, unit: settings.unit,
                                                         basis: resolved.weightBasis)
            }
            let pc = ctx?.performerContexts.first { $0.performerID == performerID }
            let lastTime = pc.flatMap { SessionRenderModel.lastTimeSegment(label: $0.label, sets: $0.lastTimeSets, unit: settings.unit) }
            let lastSet = SetHistoryText.lastSetThisSession(loggedSets(for: exercise, performerID: performerID).last, unit: settings.unit)
            return InlineEditorConfig.PerformerDefault(
                performerID: performerID, reps: resolved.reps, weightKg: weightKg,
                weight: weightKg.map { Format.weightValue($0, unit: settings.unit) } ?? "",
                weightSourceText: weightSourceText(for: resolved.weightBasis,
                                                   performerID: performerID,
                                                   exerciseName: exercise.name),
                lastTimeText: lastTime, lastSetThisSession: lastSet)
        }
    }

    func loggedSets(for exercise: Exercise, performerID: UUID?) -> [SetEntry] {
        session.orderedSets.filter { $0.exercise?.id == exercise.id && !$0.isWarmup && setPerformedBy($0, performerID: performerID) }.sorted { $0.order < $1.order }
    }

    func loggedReps(for exercise: Exercise, performerID: UUID?) -> [Int] {
        loggedSets(for: exercise, performerID: performerID).map(\.reps)
    }

    /// The single resolution path shared with the session's pending rows, so the
    /// editor can never disagree with the row the user tapped to open it.
    func resolvedSet(for exercise: Exercise, setIndex: Int,
                             performerID: UUID?) -> PerformerSetPlanner.Resolved {
        let explicit = session.explicitPlannedSets(forPerformerID: performerID,
                                                   exerciseName: exercise.name)
        let ownerPlan = session.explicitPlannedSets(forPerformerID: nil, exerciseName: exercise.name)
            ?? session.plannedRepLadder.map {
                PlannedSetPrescription(targetReps: $0,
                                       targetWeightKg: session.prescribedLoadKg > 0 ? session.prescribedLoadKg : nil)
            }
        var history = cache.state.performerHistory(forExerciseID: exercise.id, performerID: performerID)
        if history.repLadders.isEmpty {
            history.repLadders = WorkoutRepository.repLadderHistory(
                for: exercise, performedBy: people(for: performerID), excluding: session)
        }
        if history.firstWorkingWeightKg == nil {
            history.firstWorkingWeightKg = WorkoutRepository.firstWorkingSetWeight(
                for: exercise, performedBy: people(for: performerID), excluding: session)
        }
        if history.generalRepLadders.isEmpty {
            history.generalRepLadders = generalRepLadders[SessionRenderModel.performerKey(performerID)] ?? []
        }
        if history.weightSamples.isEmpty {
            history.weightSamples = (exercise.sets ?? [])
                .filter { $0.session?.id != session.id && !$0.isWarmup && setPerformedBy($0, performerID: performerID) }
                .map(SetSample.from)
        }
        history.repsLoggedThisSession = loggedReps(for: exercise, performerID: performerID)
        history.lastWeightThisSessionKg = loggedSets(for: exercise, performerID: performerID).last?.weight
        // What they lifted for this movement *today* is a better starting load
        // than what they opened with last time.
        if let last = SessionViewModel.lastSessionWeight(session: session, exercise: exercise,
                                                         performerID: performerID) {
            history.firstWorkingWeightKg = last
        }
        return PerformerSetPlanner.resolve(
            setIndex: setIndex,
            performerPlan: explicit,
            ownerPlan: ownerPlan,
            // The coach ladder is the owner's prescription. A returning partner
            // gets their own established rep pattern instead.
            ownerLadder: SessionViewModel.effectiveLadder(session: session),
            isOwner: performerID == nil,
            history: history,
            formula: settings.formula)
    }

    private func weightSourceText(for basis: PerformerSetPlanner.WeightBasis,
                                  performerID: UUID?, exerciseName: String) -> String? {
        let performer = performerID.flatMap(people(for:))?.name ?? "your"
        switch basis {
        case .explicitPlan:
            return performerID == nil ? "From your workout plan" : "From \(performer)'s workout plan"
        case .ownerPlan:
            return "From the workout plan"
        case .currentSession:
            return "Same load as your previous set today"
        case .exactHistory:
            return "Matched \(performer)'s previous \(exerciseName) set · rounded to a loadable increment"
        case .estimatedHistory:
            return "Estimated from \(performer)'s previous \(exerciseName) sets · rounded to a loadable increment"
        case .priorHistory:
            return "From \(performer)'s previous \(exerciseName) history · rounded to a loadable increment"
        case .none:
            return nil
        }
    }

}
