import Foundation
import SwiftData
import WatchConnectivity
import CadenceCore
import CadenceFeatures

/// 10-minute inactivity watchdog for Watch-started/resumed STRENGTH workouts. Cardio, swim,
/// interval and monitoring never create a record. The durable record (not the task) is the source
/// of truth: the task is best-effort and every launch/recovery/HK callback reconciles it.
extension WatchWorkoutManager {
    var strengthInactivity: WatchStrengthInactivityTracker { WatchStrengthInactivityTracker() }

    private var inactivityEnabled: Bool { watchAppSettings?.autoEndOnIdle ?? true }
    private var inactivityTimeoutMinutes: Int { watchAppSettings?.idleTimeoutMinutes ?? 10 }

    /// Called once the local strength `WorkoutSession` exists (start, or user-chosen resume).
    func beginStrengthInactivityTracking(sessionID: UUID, explicitResume: Bool, now: Date = Date()) {
        guard !uiTestMode else { return }
        reconcileWatchStrengthInactivity(now: now)
        guard let record = strengthInactivity.begin(
            sessionID: sessionID, now: now, timeoutMinutes: inactivityTimeoutMinutes,
            enabled: inactivityEnabled) else { return }
        if explicitResume { recordStrengthMeaningfulActivity(.userResume, now: now) } else { armStrengthInactivityDeadline(record) }
    }

    /// The single entry point for activity. Callers are real Watch gestures only (set log/edit/
    /// delete, add/remove exercise or partner, pause/resume/finish). Never HR, appearance,
    /// WatchConnectivity, HealthKit or recovery paths.
    func recordStrengthMeaningfulActivity(_ event: StrengthActivityEvent, now: Date = Date()) {
        guard !uiTestMode, strengthInactivity.record != nil else { return }
        if let record = strengthInactivity.recordActivity(event, now: now) {
            armStrengthInactivityDeadline(record)
        } else {
            reconcileWatchStrengthInactivity(now: now) // overdue: reconciliation owns it
        }
    }

    func armStrengthInactivityDeadline(_ record: WatchStrengthInactivityRecord, now: @escaping @Sendable () -> Date = { Date() }) {
        inactivityTask?.cancel()
        let delay = max(0, record.deadline.timeIntervalSince(now()))
        inactivityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reconcileWatchStrengthInactivity(now: now())
        }
    }

    /// Not activity. Safe from launch, recovery, HK callbacks, HR wakeups and screen wake; it only
    /// compares `now` with the STORED deadline.
    func reconcileWatchStrengthInactivity(now: Date = Date()) {
        guard !uiTestMode else { return }
        switch strengthInactivity.evaluate(now: now, enabled: inactivityEnabled) {
        case .finalize(let record, let endedAt):
            Task { await autoFinishStrengthForInactivity(sessionID: record.sessionID, endedAt: endedAt) }
        case .waiting(let until):
            if inactivityTask == nil, let record = strengthInactivity.record, record.deadline == until {
                armStrengthInactivityDeadline(record)
            }
        case .noRecord, .disabled:
            break
        }
    }

    /// Ends tracking after an explicit finish/discard (called from `stopWorkout`).
    func endStrengthInactivityTracking() {
        inactivityTask?.cancel(); inactivityTask = nil
        strengthInactivity.clear()
    }

    /// Idempotent. Validates the record, finalizes the local session at `endedAt` (the stored
    /// deadline), enqueues the same `end_session` route as a normal finish (marked with a reason),
    /// stops the `HKWorkoutSession` once, clears the record and leaves a durable notice.
    func autoFinishStrengthForInactivity(sessionID: UUID, endedAt: Date) async {
        let tracker = strengthInactivity
        guard let record = tracker.record, record.sessionID == sessionID, !inactivityFinishing,
              let container = strengthModelContainer else { return }
        inactivityFinishing = true
        defer { inactivityFinishing = false }
        inactivityTask?.cancel(); inactivityTask = nil

        // Snapshot HR before any teardown.
        let capture = isActive && workoutType == "strength" ? finalizeStrengthHRCapture() : nil
        let context = container.mainContext
        let now = Date()
        let outcome = WatchStrengthInactivityFinalizer.finalize(
            sessionID: sessionID, endedAt: endedAt, now: now, context: context)

        if outcome == .finalized {
            var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })
            descriptor.fetchLimit = 1
            if let session = try? context.fetch(descriptor).first {
                let model = WatchStrengthFlowModel(context: context)
                model.start(resuming: session)
                completeStrengthWorkout(model: model, capture: capture?.samples ?? [], endReason: .inactivity)
            }
        }

        if isActive, workoutType == "strength", phoneRequestID == nil { stopWorkout(save: false) }
        resetFinalizedStrengthCapture()
        tracker.clear(matching: record.sessionGeneration)
        if outcome != .missingSession {
            let notice = WatchStrengthInactivityNotice(
                sessionID: sessionID, endedAt: endedAt, timeoutMinutes: record.timeoutMinutes,
                keptSets: outcome == .finalized)
            tracker.store.saveNotice(notice)
            strengthInactivityNotice = notice
        }
        strengthInactivityEndedSessionID = sessionID
        CadenceWatchWidgetStore.clear()
    }

    func dismissStrengthInactivityNotice() {
        strengthInactivity.store.saveNotice(nil)
        strengthInactivityNotice = nil
    }
}
