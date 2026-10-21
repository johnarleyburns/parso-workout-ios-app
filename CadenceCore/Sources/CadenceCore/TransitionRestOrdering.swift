import Foundation

/// Deterministic exercise-order optimizer driven only by the separated
/// transition-rest model (`StrengthItem.effectiveTransitionRestSeconds`).
///
/// The pause after the final exercise of a session is never taken, so the
/// total transition rest a session pays is the sum over every unit except the
/// last. Ending on the unit with the longest transition therefore removes the
/// most waiting. Set content and between-set rest are never touched.
public enum TransitionRestOrdering {
    public struct Result: Equatable, Sendable {
        public let session: Session
        /// Total transition rest actually taken, before and after.
        public let transitionRestBeforeSeconds: Int
        public let transitionRestAfterSeconds: Int
        public var didReorder: Bool { transitionRestAfterSeconds != transitionRestBeforeSeconds || movedItemIDs.isEmpty == false }
        /// IDs of items whose position changed.
        public let movedItemIDs: [UUID]
        public var savedSeconds: Int { transitionRestBeforeSeconds - transitionRestAfterSeconds }
    }

    /// A unit is a single item or a run of consecutive items sharing a
    /// superset group; units move as a whole with internal order preserved.
    private struct Unit {
        var items: [WorkoutItem]
        var movable: Bool
        var transition: Int
    }

    /// - Parameter pinnedItemIDs: items that must keep their position
    ///   (user-authored order). Non-strength items are always pinned.
    public static func optimize(_ session: Session,
                                pinnedItemIDs: Set<UUID> = []) -> Result {
        let ordered = session.orderedItems
        let slotOrders = ordered.map(\.order)
        let units = makeUnits(ordered, pinned: pinnedItemIDs)
        let before = totalTransition(units)

        var result = units
        if let last = units.last, last.movable {
            let movableIdx = units.indices.filter { units[$0].movable }
            // Longest transition wins; ties keep the earliest original unit
            // unless the current last already ties (then nothing moves).
            var best = movableIdx.last!
            for i in movableIdx where units[i].transition > units[best].transition {
                best = i
            }
            if best != units.count - 1 {
                let moving = units[best]
                var rest = movableIdx.filter { $0 != best }.map { units[$0] }
                rest.append(moving)
                result = units
                for (slot, idx) in movableIdx.enumerated() { result[idx] = rest[slot] }
            }
        }

        let flat = result.flatMap(\.items)
        var newItems: [WorkoutItem] = []
        var moved: [UUID] = []
        for (position, item) in flat.enumerated() {
            if item.id != ordered[position].id { moved.append(item.id) }
            newItems.append(item.withOrder(slotOrders[position]))
        }
        var out = session
        out.items = newItems
        return Result(session: out,
                      transitionRestBeforeSeconds: before,
                      transitionRestAfterSeconds: totalTransition(result),
                      movedItemIDs: moved)
    }

    private static func makeUnits(_ ordered: [WorkoutItem], pinned: Set<UUID>) -> [Unit] {
        var units: [Unit] = []
        var currentGroup: SupersetGroupID?
        for item in ordered {
            guard case let .strength(s) = item else {
                units.append(Unit(items: [item], movable: false, transition: 0))
                currentGroup = nil
                continue
            }
            let isPinned = pinned.contains(s.id)
            if let g = s.supersetGroup, g == currentGroup, var u = units.popLast() {
                u.items.append(item)
                u.movable = u.movable && !isPinned
                u.transition = s.effectiveTransitionRestSeconds ?? 0
                units.append(u)
            } else {
                units.append(Unit(items: [item], movable: !isPinned,
                                  transition: s.effectiveTransitionRestSeconds ?? 0))
            }
            currentGroup = s.supersetGroup
        }
        return units
    }

    private static func totalTransition(_ units: [Unit]) -> Int {
        units.dropLast().reduce(0) { $0 + $1.transition }
    }
}

private extension WorkoutItem {
    func withOrder(_ order: Int) -> WorkoutItem {
        switch self {
        case var .strength(i): i.order = order; return .strength(i)
        case var .cardio(i): i.order = order; return .cardio(i)
        case var .mobility(i): i.order = order; return .mobility(i)
        case var .instruction(i): i.order = order; return .instruction(i)
        }
    }
}

/// Production entry point: orders a freshly generated suggestion with the
/// transition-rest model, after exercise eligibility and coverage selection
/// and before the plan reaches the preview, the active session or the Watch.
///
/// Cost model (the only one): the documented transition-rest total of
/// `TransitionRestOrdering` — every unit's transition rest except the last.
/// Generated exercises carry no authored rest, so each is costed with the
/// product default below, chosen by `Mechanics`. This is a scheduling
/// heuristic, not a physiological claim, and it changes only the order:
/// sets, reps and rest prescriptions are never touched.
public enum GeneratedTransitionRestOrder {
    /// Editable product defaults used only as the ordering cost.
    public static func costSeconds(for mechanics: Mechanics) -> Int {
        switch mechanics {
        case .compound: 180
        case .isolation: 90
        }
    }

    /// Returns `option` with exercises (and the plan items that mirror them)
    /// reordered. Any option the optimizer cannot prove safe is returned
    /// unchanged: engine-authored plans (their order belongs to the stored
    /// engine plan), empty or single-exercise options, duplicate candidates,
    /// or a result that is not an exact permutation of the input.
    public static func apply(to option: SuggestedWorkoutOption) -> SuggestedWorkoutOption {
        let exercises = option.exercises
        guard option.enginePlanID == nil, exercises.count > 1,
              option.plan.items.count == exercises.count,
              Set(exercises.map(\.candidateID)).count == exercises.count else { return option }

        let items = exercises.enumerated().map { index, exercise in
            StrengthItem(
                exerciseKey: ExerciseKey(raw: exercise.candidateID), order: index,
                defaultRestSeconds: nil,
                sets: [PrescribedSet(setIndex: 0, repTarget: .exact(exercise.repRange.lowerBound))],
                schemeApplied: nil, supersetGroup: nil, laterality: nil,
                progression: nil, performerOverrides: nil,
                transitionRestSeconds: costSeconds(for: exercise.mechanics))
        }
        let indexByItemID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })
        let result = TransitionRestOrdering.optimize(
            Session(title: option.plan.name, items: items.map { .strength($0) }))
        let permutation: [Int] = result.session.orderedItems.compactMap {
            if case let .strength(s) = $0 { return indexByItemID[s.id] }
            return nil
        }
        guard permutation.count == exercises.count,
              Set(permutation).count == exercises.count,
              permutation != Array(0..<exercises.count) else { return option }

        let plan = option.plan
        let reorderedItems = permutation.enumerated().map { position, original in
            let item = plan.items[original]
            return PlanItem(id: position, movement: item.movement, reps: item.reps,
                            distanceM: item.distanceM, loadLb: item.loadLb,
                            loadLbFemale: item.loadLbFemale, targetSets: item.targetSets,
                            note: item.note, loadPercentage: item.loadPercentage)
        }
        return SuggestedWorkoutOption(
            style: option.style,
            plan: WorkoutPlan(id: plan.id, name: plan.name, source: plan.source,
                              scheme: plan.scheme, items: reorderedItems,
                              notes: plan.notes, flexibleScheme: plan.flexibleScheme),
            exercises: permutation.map { exercises[$0] },
            initialDeficits: option.initialDeficits,
            remainingDeficits: option.remainingDeficits,
            plannedSetTotal: option.plannedSetTotal,
            capTrimmingOccurred: option.capTrimmingOccurred,
            citationIDs: option.citationIDs,
            enginePlanID: option.enginePlanID,
            engineRevisionID: option.engineRevisionID,
            enginePlanJSON: option.enginePlanJSON,
            rationale: option.rationale,
            unsupportedCoverage: option.unsupportedCoverage)
    }
}
