import Foundation
import SwiftData
import Observation
import CadenceCore

public struct WatchSetHistoryLine: Equatable, Sendable, Identifiable {
    public var id: Int
    public var setID: UUID?
    public var label: String
    public var weightText: String
    public var reps: Int
    public var rpe: Double?
    public var isWarmup: Bool

    public init(id: Int, setID: UUID? = nil, label: String, weightText: String,
                reps: Int, rpe: Double? = nil, isWarmup: Bool) {
        self.id = id
        self.setID = setID
        self.label = label
        self.weightText = weightText
        self.reps = reps
        self.rpe = rpe
        self.isWarmup = isWarmup
    }
}

public struct WatchPerformerOption: Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let name: String
    public let isMe: Bool

    public init(index: Int, name: String, isMe: Bool) {
        self.index = index
        self.name = name
        self.isMe = isMe
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
    public var effortMode: WatchEffortMode = .rpe
    public var effortValue: Double?
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
    private var exercisePendingAfterRest: Exercise?

    /// In-memory name → Exercise catalog, loaded once per flow so the per-tap
    /// path never refetches the full exercise table (~900 seeded rows — the
    /// dominant per-tap cost on the watch CPU). `findOrCreateExercise` is only
    /// hit on a cache miss (custom exercises, first-seen names).
    private var exerciseCache: [String: Exercise]?

    /// Prior sets are memoized per exercise + lifter. Partner histories must not
    /// reuse the owner's cache entry or all lifters appear lumped together.
    private var priorSetsByExerciseAndPerformer: [String: [SetEntry]] = [:]

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
                      initialPartnerNames: [String] = [],
                      createSession: Bool = false) {
        priorSetsByExerciseAndPerformer.removeAll()
        exerciseCache = nil
        if let existingSession {
            session = existingSession
            hydratePartners(from: existingSession)
        } else if createSession, session == nil {
            loadInitialPartners(initialPartnerNames)
            beginSession(title: title)
        } else if partners.isEmpty {
            loadInitialPartners(initialPartnerNames)
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

    // MARK: - Cached lookups (watch latency: never refetch the full table per tap)

    private func exercise(named name: String) -> Exercise? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if exerciseCache == nil {
            exerciseCache = Dictionary(
                ((try? WorkoutRepository.allExercises(context)) ?? []).map { ($0.name, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        if let cached = exerciseCache?[key] { return cached }
        guard let resolved = try? WorkoutRepository.findOrCreateExercise(named: key, in: context) else {
            return nil
        }
        exerciseCache?[resolved.name] = resolved
        return resolved
    }

    private func priorSets(for exercise: Exercise) -> [SetEntry] {
        let performer = currentPerformer
        let key = exercise.id.uuidString + "|" + (performer?.id.uuidString ?? "owner")
        if let cached = priorSetsByExerciseAndPerformer[key] { return cached }
        let sets = WorkoutRepository.lastTimeSets(for: exercise,
                                                  performedBy: performer,
                                                  excluding: session)
        priorSetsByExerciseAndPerformer[key] = sets
        return sets
    }

    private func repLadders(from prior: [SetEntry]) -> [[Int]] {
        let working = prior.filter { !$0.isWarmup }
        let grouped = Dictionary(grouping: working) { $0.session?.id ?? UUID() }
        return Array(grouped.values)
            .sorted { ($0.first?.session?.date ?? .distantPast) < ($1.first?.session?.date ?? .distantPast) }
            .map { $0.sorted { $0.order < $1.order }.map(\.reps) }
    }

    public func goToAddExercise() { stage = .addExercise }

    public func addExercise(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let exercise = exercise(named: trimmed) {
            addResolvedExercise(exercise)
            return
        }
        stage = .home
        refreshExerciseList()
    }

    /// Creates a named exercise from the watch's compact body-part pills, then
    /// adds it to the current workout exactly like a built-in search result.
    @discardableResult
    public func addCustomExercise(named name: String, bodyParts: Set<BodyPart>) -> Exercise? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !bodyParts.isEmpty else { return nil }
        guard let exercise = try? WorkoutRepository.findOrCreateExercise(
            named: trimmed,
            category: WatchCustomExerciseDefinition.category(for: bodyParts),
            primaryMuscles: WatchCustomExerciseDefinition.primaryMuscles(for: bodyParts),
            in: context
        ) else { return nil }
        exerciseCache?[exercise.name] = exercise
        addResolvedExercise(exercise)
        return exercise
    }

    private func addResolvedExercise(_ exercise: Exercise) {
        let resolved = exercise.name
        if let session {
            if !session.plannedExerciseNames.contains(where: { $0.compare(resolved, options: .caseInsensitive) == .orderedSame }) {
                session.plannedExerciseNames.append(resolved)
            }
        } else if !pendingExercises.contains(where: { $0.compare(resolved, options: .caseInsensitive) == .orderedSame }) {
            pendingExercises.append(resolved)
        }
        // Update the visible workout before SwiftData persistence. Saving can
        // take multiple watch run-loop turns when the catalog is large.
        stage = .home
        refreshExerciseList()
        Task { @MainActor [weak self] in
            await Task.yield()
            try? self?.context.save()
        }
    }

    public func startLogSet(for exercise: Exercise) {
        currentReps = Double(defaultReps(for: exercise))
        isWarmupSet = false
        effortMode = .rpe
        effortValue = nil
        // Preserve the exact last working/prescribed load. Cable stacks and
        // specialty machines commonly use decimal values that must survive
        // reopening the keypad instead of being snapped to a plate boundary.
        let lastWork = session.flatMap {
            SessionViewModel.lastSessionWeight(session: $0, exercise: exercise,
                                               performerID: currentPerformer?.id)
        } ?? priorSets(for: exercise).first {
            !$0.isWarmup && $0.weight > 0 && belongsToCurrentPerformer($0)
        }?.weight
        let prescribed = (session.map { SessionViewModel.isPrescribedMovement(exercise.name, session: $0) } == true)
            ? (session?.prescribedLoadKg ?? 0)
            : 0
        if let lastWork {
            currentWeight = lastWork
        } else if prescribed > 0 {
            currentWeight = prescribed
        } else {
            currentWeight = unit == .pounds ? WorkoutMath.canonical(45, from: .pounds) : 20
        }
        stage = .keypad(exercise)
    }

    public func toggleWarmup() { isWarmupSet.toggle() }

    public func goToPartners() { stage = .partners }

    public func goBackToHome() { stage = .home }

    public func logSet() -> SetEntry? {
        logCurrentSet(goToRest: true)
    }

    public func logLastSet() -> SetEntry? {
        logCurrentSet(goToRest: false)
    }

    private func logCurrentSet(goToRest: Bool) -> SetEntry? {
        guard case .keypad(let exercise) = stage else { return nil }

        ensureSession()
        guard let session else { return nil }

        do {
            let performer = currentPerformer
            let set = try WorkoutRepository.addSet(
                to: session, exercise: exercise, weightKg: currentWeight,
                reps: Int(currentReps), rpe: resolvedEffortRPE, isWarmup: isWarmupSet,
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
            updateExerciseListAfterLogging(exercise)
            if goToRest {
                exercisePendingAfterRest = exercise
                restTimer.start(seconds: restDefault)
                stage = .rest
            } else {
                exercisePendingAfterRest = nil
                stage = .home
            }
            return set
        } catch {
            return nil
        }
    }

    public func finishRest() {
        guard let exercise = exercisePendingAfterRest else {
            stage = .home
            return
        }
        exercisePendingAfterRest = nil
        startLogSet(for: exercise)
    }

    public func addRestTime(_ seconds: Int) { restTimer.add(seconds) }

    @discardableResult
    public func deleteExercise(_ exercise: Exercise) -> [String: Any]? {
        if let session {
            do {
                _ = try WorkoutRepository.removeExercise(exercise, from: session, in: context)
                refreshExerciseList()
                recomputeTotals()
                let payload: [String: Any] = [
                    "action": "delete_exercise",
                    "session_id": session.id.uuidString,
                    "exercise": exercise.name,
                    "timestamp": Date().timeIntervalSince1970,
                ]
                lastSyncPayload = payload
                return payload
            } catch {
                return nil
            }
        } else {
            pendingExercises.removeAll {
                $0.compare(exercise.name, options: .caseInsensitive) == .orderedSame
            }
            refreshExerciseList()
            return nil
        }
    }

    @discardableResult
    public func deleteCurrentExercise() -> [String: Any]? {
        guard case .keypad(let exercise) = stage else { return nil }
        let payload = deleteExercise(exercise)
        stage = .home
        return payload
    }

    @discardableResult
    public func deleteSet(id setID: UUID) -> [String: Any]? {
        guard let session,
              let set = session.orderedSets.first(where: { $0.id == setID }) else { return nil }
        do {
            try WorkoutRepository.deleteSet(set, in: context)
            refreshExerciseList()
            recomputeTotals()
            let payload: [String: Any] = [
                "action": "delete_set",
                "session_id": session.id.uuidString,
                "set_id": setID.uuidString,
                "timestamp": Date().timeIntervalSince1970,
            ]
            lastSyncPayload = payload
            return payload
        } catch {
            return nil
        }
    }

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
        let removedPerformerIndex = index + 1
        if currentPerformerIndex == removedPerformerIndex {
            currentPerformerIndex = 0
        } else if currentPerformerIndex > removedPerformerIndex {
            currentPerformerIndex -= 1
        } else if currentPerformerIndex > partners.count {
            currentPerformerIndex = 0
        }
    }

    public func selectPerformer(at index: Int) {
        currentPerformerIndex = min(max(0, index), partners.count)
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
        priorSetsByExerciseAndPerformer.removeAll()
        do {
            session = try WorkoutRepository.createSession(
                title: title,
                partnerIDs: partners.map { $0.id.uuidString },
                in: context
            )
            session?.originDevice = "watch"
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

    private func loadInitialPartners(_ names: [String]) {
        var seen = Set<String>()
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  seen.insert(trimmed.lowercased()).inserted else { continue }
            do {
                let person = try WorkoutRepository.findOrCreatePerson(named: trimmed, in: context)
                if !partners.contains(where: { $0.id == person.id }) {
                    partners.append(person)
                }
            } catch {}
        }
    }

    private func hydratePartners(from session: WorkoutSession) {
        partners.removeAll()
        currentPerformerIndex = 0
        let ids = session.activePartnerIDs.compactMap(UUID.init(uuidString:))
        guard !ids.isEmpty else { return }
        let people = (try? WorkoutRepository.allPeople(context)) ?? []
        for id in ids {
            if let person = people.first(where: { $0.id == id && !$0.isMe }) {
                partners.append(person)
            }
        }
    }

    private func refreshExerciseList() {
        guard let session else {
            let pending = pendingExercises.compactMap { name -> (exercise: Exercise, setCount: Int)? in
                guard let exercise = exercise(named: name) else {
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
            guard let ex = exercise(named: name),
                  !seen.contains(ex.id) else { continue }
            seen.insert(ex.id)
            rows.append((ex, 0))
        }

        exerciseList = rows
        exerciseCount = session.exercisesInOrder.count
    }

    private func updateExerciseListAfterLogging(_ exercise: Exercise) {
        if let index = exerciseList.firstIndex(where: { $0.exercise.id == exercise.id }) {
            exerciseList[index].setCount += 1
        } else {
            exerciseList.append((exercise, 1))
        }
        exerciseCount = session?.exercisesInOrder.count ?? exerciseList.count
    }

    private func recomputeTotals() {
        guard let session else {
            volume = 0
            setCount = 0
            exerciseCount = 0
            return
        }
        let working = session.orderedSets.filter { !$0.isWarmup && $0.isOwnerSet }
        setCount = working.count
        volume = working.reduce(0) {
            $0 + WorkoutMath.volume(weight: $1.effectiveLoadKg, reps: $1.reps)
        }
        exerciseCount = session.exercisesInOrder.count
    }

    private func resolvedExerciseName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return exercise(named: trimmed)?.name ?? trimmed
    }

    private var currentPerformer: Person? {
        guard !partners.isEmpty, currentPerformerIndex > 0 else { return nil }
        let partnerIndex = currentPerformerIndex - 1
        guard partnerIndex < partners.count else { return nil }
        return partners[partnerIndex]
    }

    public var performerLabel: String? {
        guard !partners.isEmpty else { return nil }
        return currentPerformer?.name ?? "Me"
    }

    public var performerOptions: [WatchPerformerOption] {
        guard !partners.isEmpty else { return [] }
        return [WatchPerformerOption(index: 0, name: "Me", isMe: true)]
            + partners.enumerated().map { offset, partner in
                WatchPerformerOption(index: offset + 1, name: partner.name, isMe: false)
            }
    }

    public var resolvedEffortRPE: Double? {
        effortMode.rpeValue(from: effortValue)
    }

    private func advancePerformer() {
        let total = partners.count
        guard total > 0 else { return }
        currentPerformerIndex = (currentPerformerIndex + 1) % (total + 1)
    }

    public var previousSetHint: String? {
        guard case .keypad(let exercise) = stage else { return nil }
        let working = priorSets(for: exercise).filter {
            !$0.isWarmup && belongsToCurrentPerformer($0)
        }
        guard let last = working.last else { return nil }
        return "Previous: \(Format.previousShort(last.effectiveLoadKg, reps: last.reps, unit: unit))"
    }

    public var previousWorkoutHistoryLines: [WatchSetHistoryLine] {
        guard case .keypad(let exercise) = stage else { return [] }
        return historyLines(from: priorSets(for: exercise).filter(belongsToCurrentPerformer))
    }

    public var currentWorkoutHistoryLines: [WatchSetHistoryLine] {
        guard case .keypad(let exercise) = stage, let session else { return [] }
        let sets = session.orderedSets.filter {
            $0.exercise?.id == exercise.id && belongsToCurrentPerformer($0)
        }
        return historyLines(from: sets)
    }

    public var currentWorkingSetIndex: Int {
        guard case .keypad = stage else { return 1 }
        let completed = currentWorkoutHistoryLines.filter { !$0.isWarmup }.count
        return completed + 1
    }

    public func weightValue(_ kg: Double) -> String {
        Format.weightValue(kg, unit: unit, decimals: 0)
    }

    /// The working weight expressed in the user's display unit (lb/kg). The watch
    /// keypad binds this so the digital crown can select decimal display-unit
    /// values while plate shortcuts make larger changes; canonical-kg storage stays in
    /// `currentWeight`. Reading/writing here converts, so the two never drift.
    public var currentWeightDisplay: Double {
        get { WorkoutMath.display(currentWeight, in: unit) }
        set { currentWeight = WorkoutMath.canonical(newValue, from: unit) }
    }

    /// The current weight formatted for the keypad to one practical crown
    /// detent (e.g. "47.5") while trimming a trailing ".0".
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
                .filter { $0.exercise?.id == exercise.id && !$0.isWarmup && belongsToCurrentPerformer($0) }
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

        let prior = repLadders(from: priorSets(for: exercise).filter(belongsToCurrentPerformer))
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
                    setID: set.id,
                    label: "W",
                    weightText: Format.weightValue(set.effectiveLoadKg, unit: unit, decimals: 1),
                    reps: set.reps,
                    rpe: set.rpe,
                    isWarmup: true
                )
            }
            workingIndex += 1
            return WatchSetHistoryLine(
                id: offset,
                setID: set.id,
                label: "\(workingIndex)",
                weightText: Format.weightValue(set.effectiveLoadKg, unit: unit, decimals: 1),
                reps: set.reps,
                rpe: set.rpe,
                isWarmup: false
            )
        }
    }

    private func belongsToCurrentPerformer(_ set: SetEntry) -> Bool {
        if let performer = currentPerformer {
            return set.performedBy?.id == performer.id
        }
        return set.isOwnerSet
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
        if let rpe = set.rpe {
            dict["rpe"] = rpe
            dict["effort_mode"] = effortMode.rawValue
            dict["effort_value"] = effortValue
        }
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
        var payload: [String: Any] = [
            "action": "end_session",
            "session_id": session.id.uuidString,
            "ended_at": (session.endedAt ?? Date()).timeIntervalSince1970,
            "cooldown_seconds": Int(session.cooldownSeconds),
            "session_title": session.title,
            "planned_exercises": session.plannedExerciseNames,
            "planned_rep_ladder": session.plannedRepLadder,
            "exercises": session.exercisesInOrder.map { $0.name },
        ]
        if let planKey = session.planKey {
            payload["plan_key"] = planKey
        }
        return payload
    }
}
