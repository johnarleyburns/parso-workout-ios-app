import Foundation
import SwiftData
import Observation
import CadenceCore

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

    public func start() {
        stage = .home
        refreshExerciseList()
    }

    public func goToAddExercise() { stage = .addExercise }

    public func addExercise(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            _ = try WorkoutRepository.findOrCreateExercise(named: trimmed, in: context)
            if let session {
                if !session.plannedExerciseNames.contains(trimmed) {
                    session.plannedExerciseNames.append(trimmed)
                    try? context.save()
                }
            } else if !pendingExercises.contains(trimmed) {
                pendingExercises.append(trimmed)
            }
        } catch {}
        stage = .home
        refreshExerciseList()
    }

    public func startLogSet(for exercise: Exercise) {
        currentWeight = 20
        currentReps = 8
        isWarmupSet = false
        let lastWork = (exercise.sets ?? []).last(where: { !$0.isWarmup && $0.isOwnerSet })
        if let lastWork { currentWeight = lastWork.effectiveLoadKg }
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
        do {
            session = try WorkoutRepository.createSession(
                title: "Strength",
                partnerIDs: partners.map { $0.id.uuidString },
                in: context
            )
            session?.plannedExerciseNames = pendingExercises
            for name in pendingExercises {
                _ = try WorkoutRepository.findOrCreateExercise(named: name, in: context)
            }
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
        let working = (exercise.sets ?? []).filter { !$0.isWarmup && $0.isOwnerSet }
        guard let last = working.last else { return nil }
        return "Previous: \(Format.previousShort(last.effectiveLoadKg, reps: last.reps, unit: unit))"
    }

    public func weightValue(_ kg: Double) -> String {
        Format.weightValue(kg, unit: unit, decimals: 0)
    }

    public var durationText: String {
        guard let session else { return "0:00" }
        let dur = max(0, (session.endedAt ?? Date()).timeIntervalSince(session.date))
        let total = Int(dur)
        return String(format: "%d:%02d", total / 60, total % 60)
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
        ]
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
