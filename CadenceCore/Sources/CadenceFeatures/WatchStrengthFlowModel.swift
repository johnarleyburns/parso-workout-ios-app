import Foundation
import SwiftData
import Observation
import CadenceCore

public struct WatchSetHistoryLine: Equatable, Sendable, Identifiable {
    public var id: Int
    public var label: String
    public var weightText: String
    public var reps: Int
    public var isWarmup: Bool

    public init(id: Int, label: String, weightText: String, reps: Int, isWarmup: Bool) {
        self.id = id
        self.label = label
        self.weightText = weightText
        self.reps = reps
        self.isWarmup = isWarmup
    }
}

@Observable
public final class WatchStrengthFlowModel {
    public enum Stage: Equatable {
        case idle
        case home
        case addExercise
        case keypad(Exercise)
        case partners
        case rest
        case cooldown(TimeInterval)
        case summary
        case discarded
    }

    public private(set) var stage: Stage = .home
    public private(set) var session: WorkoutSession?
    public private(set) var exerciseList: [(exercise: Exercise, setCount: Int)] = []
    public private(set) var pendingExercises: [String] = []
    public var currentWeight: Double = 20
    public var currentReps: Double = 8
    public var isWarmupSet: Bool = false
    public private(set) var partners: [Person] = []
    public private(set) var currentPerformerIndex: Int = 0
    public private(set) var restTimer: RestTimerModel
    public private(set) var cooldownTimerModel: RestTimerModel
    public private(set) var volume: Double = 0
    public private(set) var setCount: Int = 0
    public private(set) var exerciseCount: Int = 0

    public var discardPayload: [String: Any]?
    public var lastSyncPayload: [String: Any]?
    public var lastPerformedByName: String?

    public let unit: MeasurementUnitPreference
    let cooldownDefault: Int
    let restDefault: Int
    private let context: ModelContext

    public init(context: ModelContext, unit: MeasurementUnitPreference = .kilograms,
                cooldownDefault: Int = 5, restDefault: Int = 90) {
        self.context = context
        self.unit = unit
        self.cooldownDefault = cooldownDefault
        self.restDefault = restDefault
        self.restTimer = RestTimerModel()
        self.cooldownTimerModel = RestTimerModel()
    }

    public func start(resuming existingSession: WorkoutSession? = nil,
                      title: String = "Strength",
                      plannedExerciseNames: [String] = [],
                      repLadder: [Int] = [],
                      planKey: String? = nil,
                      createSession: Bool = false) {
        if let existingSession {
            session = existingSession
        } else if createSession, session == nil {
            beginSession(title: title)
        }
        if let session {
            if !plannedExerciseNames.isEmpty {
                for name in plannedExerciseNames {
                    let resolved = resolvedExerciseName(name)
                    guard !resolved.isEmpty,
                          !session.plannedExerciseNames.contains(where: { $0.compare(resolved, options: .caseInsensitive) == .orderedSame }) else {
                        continue
                    }
                    session.plannedExerciseNames.append(resolved)
                }
            }
            if !repLadder.isEmpty {
                session.plannedRepLadder = repLadder
            }
            if let planKey {
                session.planKey = planKey
            }
            try? context.save()
        } else {
            for name in plannedExerciseNames {
                let resolved = resolvedExerciseName(name)
                guard !resolved.isEmpty,
                      !pendingExercises.contains(where: { $0.compare(resolved, options: .caseInsensitive) == .orderedSame }) else {
                    continue
                }
                pendingExercises.append(resolved)
            }
        }
        stage = .home
        refreshExerciseList()
    }

    public func goToAddExercise() { stage = .addExercise }

    public func addExercise(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let exercise = try WorkoutRepository.findOrCreateExercise(named: trimmed, in: context)
            let resolved = exercise.name
            if let session {
                if !session.plannedExerciseNames.contains(where: { $0.compare(resolved, options: .caseInsensitive) == .orderedSame }) {
                    session.plannedExerciseNames.append(resolved)
                    try? context.save()
                }
            } else if !pendingExercises.contains(where: { $0.compare(resolved, options: .caseInsensitive) == .orderedSame }) {
                pendingExercises.append(resolved)
            }
        } catch {}
        stage = .home
        refreshExerciseList()
    }

    public func startLogSet(for exercise: Exercise) {
        currentReps = Double(defaultReps(for: exercise))
        isWarmupSet = false
        // Default to the last working weight for this exercise (or a 20 kg
        // empty-bar baseline), snapped to the nearest 2.5 in the user's display
        // unit. Without the snap a canonical-kg value shows as an odd "44 lb".
        let lastWork = session.flatMap {
            SessionViewModel.lastSessionWeight(session: $0, exercise: exercise, performerID: nil)
        } ?? WorkoutRepository.firstWorkingSetWeight(for: exercise, performedBy: nil, excluding: session)
        let prescribed = (session.map { SessionViewModel.isPrescribedMovement(exercise.name, session: $0) } == true)
            ? (session?.prescribedLoadKg ?? 0)
            : 0
        let baseKg = lastWork ?? (prescribed > 0 ? prescribed : 20)
        currentWeight = UnitEntry.plateRounded(kg: baseKg, unit: unit, increment: 2.5)
        stage = .keypad(exercise)
    }

    public func toggleWarmup() { isWarmupSet.toggle() }

    public func goToPartners() { stage = .partners }

    public func goBackToHome() { stage = .home }

    public func logSet() -> SetEntry? {
        guard case .keypad(let exercise) = stage else { return nil }

        ensureSession()
        guard let session else { return nil }

        do {
            let performer = currentPerformer
            let set = try WorkoutRepository.addSet(
                to: session, exercise: exercise, weightKg: currentWeight,
                reps: Int(currentReps), isWarmup: isWarmupSet,
                performedBy: performer?.isMe == true ? nil : performer,
                in: context
            )

            let isOwner = set.isOwnerSet
            syncLogSet(session: session, exercise: exercise, set: set)
            if !partners.isEmpty { advancePerformer() }
            if isOwner, !isWarmupSet {
                volume += WorkoutMath.volume(weight: set.effectiveLoadKg, reps: set.reps)
                setCount += 1
            }
            refreshExerciseList()
            restTimer.start(seconds: restDefault)
            stage = .rest
            return set
        } catch {
            return nil
        }
    }

    public func finishRest() { stage = .home; refreshExerciseList() }

    public func addRestTime(_ seconds: Int) { restTimer.add(seconds) }

    public func finish() {
        if session == nil {
            stage = .discarded
            return
        }
        if let session, session.orderedSets.isEmpty {
            context.delete(session)
            try? context.save()
            self.session = nil
            stage = .discarded
            return
        }
        stage = .cooldown(TimeInterval(cooldownDefault * 60))
        cooldownTimerModel.start(seconds: cooldownDefault * 60)
    }

    public func skipCooldown() {
        completeSession(cooldown: 0)
        stage = .summary
    }

    public func completeCooldown() {
        let remaining = TimeInterval(cooldownTimerModel.remaining)
        completeSession(cooldown: max(0, TimeInterval(cooldownDefault * 60) - remaining))
        stage = .summary
    }

    public func cancel() {
        if let session {
            let syncSets = !(session.sets ?? []).isEmpty
            context.delete(session)
            try? context.save()
            discardPayload = syncSets ? ["action": "discard_session", "session_id": session.id.uuidString] : nil
        }
        session = nil
        stage = .discarded
    }

    public func addPartner(named name: String) {
        do {
            let person = try WorkoutRepository.findOrCreatePerson(named: name, in: context)
            if !partners.contains(where: { $0.id == person.id }) {
                partners.append(person)
            }
            session?.activePartnerIDs = partners.map { $0.id.uuidString }
            try? context.save()
        } catch {}
    }

    public func removePartner(at index: Int) {
        guard index < partners.count else { return }
        partners.remove(at: index)
        session?.activePartnerIDs = partners.map { $0.id.uuidString }
        try? context.save()
        if currentPerformerIndex >= partners.count { currentPerformerIndex = 0 }
    }

    public func selectPerformer(at index: Int) {
        currentPerformerIndex = min(index, partners.count)
    }

    public func dismissSummary() {
        stage = .idle
    }

    // MARK: - Private

    private func ensureSession() {
        guard session == nil else { return }
        beginSession(title: "Strength")
    }

    private func beginSession(title: String) {
        guard session == nil else { return }
        do {
            session = try WorkoutRepository.createSession(
                title: title,
                partnerIDs: partners.map { $0.id.uuidString },
                in: context
            )
            var resolvedPending: [String] = []
            for name in pendingExercises {
                let resolved = resolvedExerciseName(name)
                guard !resolved.isEmpty,
                      !resolvedPending.contains(where: { $0.compare(resolved, options: .caseInsensitive) == .orderedSame }) else {
                    continue
                }
                resolvedPending.append(resolved)
            }
            session?.plannedExerciseNames = resolvedPending
            pendingExercises = []
            try? context.save()
        } catch {}
    }

    private func refreshExerciseList() {
        guard let session else {
            let pending = pendingExercises.compactMap { name -> (exercise: Exercise, setCount: Int)? in
                guard let exercise = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) else {
                    return nil
                }
                return (exercise, 0)
            }
            exerciseList = pending
            exerciseCount = 0
            return
        }

        var seen = Set<UUID>()
        var rows: [(exercise: Exercise, setCount: Int)] = []
        for ex in session.exercisesInOrder {
            seen.insert(ex.id)
            let count = session.orderedSets.filter { $0.exercise?.id == ex.id }.count
            rows.append((ex, count))
        }

        for name in session.plannedExerciseNames {
            guard let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context),
                  !seen.contains(ex.id) else { continue }
            seen.insert(ex.id)
            rows.append((ex, 0))
        }

        exerciseList = rows
        exerciseCount = session.exercisesInOrder.count
    }

    private func resolvedExerciseName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let exercise = try? WorkoutRepository.findOrCreateExercise(named: trimmed, in: context) {
            return exercise.name
        }
        return trimmed
    }

    private var currentPerformer: Person? {
        guard !partners.isEmpty, currentPerformerIndex < partners.count else { return nil }
        return partners[currentPerformerIndex]
    }

    public var performerLabel: String? {
        guard let p = currentPerformer else { return nil }
        return p.name
    }

    private func advancePerformer() {
        let total = partners.count
        guard total > 0 else { return }
        currentPerformerIndex = (currentPerformerIndex + 1) % (total + 1)
    }

    public var previousSetHint: String? {
        guard case .keypad(let exercise) = stage else { return nil }
        let working: [SetEntry]
        if let session {
            working = WorkoutRepository.lastTimeSets(for: exercise, excluding: session)
                .filter { !$0.isWarmup && $0.isOwnerSet }
        } else {
            working = (exercise.sets ?? []).filter { !$0.isWarmup && $0.isOwnerSet }
        }
        guard let last = working.last else { return nil }
        return "Previous: \(Format.previousShort(last.effectiveLoadKg, reps: last.reps, unit: unit))"
    }

    public var previousWorkoutHistoryLines: [WatchSetHistoryLine] {
        guard case .keypad(let exercise) = stage else { return [] }
        return historyLines(from: WorkoutRepository.lastTimeSets(for: exercise, excluding: session))
    }

    public var currentWorkoutHistoryLines: [WatchSetHistoryLine] {
        guard case .keypad(let exercise) = stage, let session else { return [] }
        let sets = session.orderedSets.filter { $0.exercise?.id == exercise.id }
        return historyLines(from: sets)
    }

    public var currentWorkingSetIndex: Int {
        guard case .keypad(let exercise) = stage else { return 1 }
        let completed = currentWorkoutHistoryLines.filter { !$0.isWarmup }.count
        return completed + 1
    }

    public func weightValue(_ kg: Double) -> String {
        Format.weightValue(kg, unit: unit, decimals: 0)
    }

    /// The working weight expressed in the user's display unit (lb/kg). The watch
    /// keypad binds this so the digital crown and +/- chips step in whole
    /// display-unit increments (e.g. 2.5 lb); canonical-kg storage stays in
    /// `currentWeight`. Reading/writing here converts, so the two never drift.
    public var currentWeightDisplay: Double {
        get { WorkoutMath.display(currentWeight, in: unit) }
        set { currentWeight = WorkoutMath.canonical(newValue, from: unit) }
    }

    /// The current weight formatted for the keypad, allowing a half (e.g.
    /// "47.5") but trimming a trailing ".0".
    public var currentWeightText: String {
        Format.weightValue(currentWeight, unit: unit, decimals: 1)
    }

    public var durationText: String {
        guard let session else { return "0:00" }
        let dur = max(0, (session.endedAt ?? Date()).timeIntervalSince(session.date))
        let total = Int(dur)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func defaultReps(for exercise: Exercise) -> Int {
        let currentReps: [Int]
        let setIndex: Int
        let lastLogged: Int?
        if let session {
            let sets = session.orderedSets
                .filter { $0.exercise?.id == exercise.id && !$0.isWarmup && $0.isOwnerSet }
                .sorted { $0.order < $1.order }
            currentReps = sets.map(\.reps)
            setIndex = sets.count
            lastLogged = sets.last?.reps
            if setIndex < session.plannedRepLadder.count,
               session.plannedRepLadder[setIndex] > 0 {
                return session.plannedRepLadder[setIndex]
            }
        } else {
            currentReps = []
            setIndex = 0
            lastLogged = nil
        }

        let prior = WorkoutRepository.repLadderHistory(for: exercise, performedBy: nil, excluding: session)
        if setIndex < (prior.last?.count ?? 0), let reps = prior.last?[setIndex], reps > 0 {
            return reps
        }

        return SessionViewModel.plannedReps(
            ladder: session.flatMap { SessionViewModel.effectiveLadder(session: $0) },
            setIndex: setIndex,
            currentSessionReps: currentReps,
            priorSessionLadders: prior,
            lastLoggedReps: lastLogged
        )
    }

    private func historyLines(from sets: [SetEntry]) -> [WatchSetHistoryLine] {
        var workingIndex = 0
        return sets.sorted { $0.order < $1.order }.enumerated().map { offset, set in
            if set.isWarmup {
                return WatchSetHistoryLine(
                    id: offset,
                    label: "W",
                    weightText: Format.weightValue(set.effectiveLoadKg, unit: unit, decimals: 1),
                    reps: set.reps,
                    isWarmup: true
                )
            }
            workingIndex += 1
            return WatchSetHistoryLine(
                id: offset,
                label: "\(workingIndex)",
                weightText: Format.weightValue(set.effectiveLoadKg, unit: unit, decimals: 1),
                reps: set.reps,
                isWarmup: false
            )
        }
    }

    private func completeSession(cooldown seconds: TimeInterval) {
        session?.endedAt = Date()
        session?.cooldownSeconds = seconds
        try? context.save()
    }

    private func syncLogSet(session: WorkoutSession, exercise: Exercise, set: SetEntry) {
        var dict: [String: Any] = [
            "action": "log_set",
            "session_id": session.id.uuidString,
            "set_id": set.id.uuidString,
            "exercise": exercise.name,
            "weight": set.effectiveLoadKg,
            "reps": set.reps,
            "is_warmup": set.isWarmup,
            "timestamp": Date().timeIntervalSince1970,
            "session_title": session.title,
            "planned_exercises": session.plannedExerciseNames,
            "planned_rep_ladder": session.plannedRepLadder,
        ]
        if let planKey = session.planKey {
            dict["plan_key"] = planKey
        }
        if let performer = currentPerformer {
            dict["performed_by"] = performer.name
            dict["performed_by_id"] = performer.id.uuidString
        }
        lastSyncPayload = dict
        lastPerformedByName = currentPerformer?.name
    }

    public func endSessionPayload() -> [String: Any]? {
        guard let session else { return nil }
        return [
            "action": "end_session",
            "session_id": session.id.uuidString,
            "ended_at": (session.endedAt ?? Date()).timeIntervalSince1970,
            "cooldown_seconds": Int(session.cooldownSeconds),
            "exercises": session.exercisesInOrder.map { $0.name },
        ]
    }
}
