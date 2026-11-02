import Foundation
import HealthKit
import WatchKit
import CadenceCore
import CadenceFeatures

/// Inactivity policy for Watch-owned CARDIO sessions (not strength, not interval runner, not swim).
/// The durable `WatchCardioInactivityRecord` is the truth; the deadline task is best-effort and
/// every activation, recovery, HealthKit callback and cardio-screen return reconciles it.
///
/// Every path that pauses/resumes/ends a tracked cardio session routes through this file:
/// `togglePause` -> `toggleCardioPauseIfTracked`, policy -> `pauseCardioForInactivity`,
/// terminal -> `autoFinishCardioForInactivity`, user End/discard -> `finishCardioSession`
/// (which clears the record). Fallback for swim / intervals / monitoring / pre-migration
/// sessions without a record: no automatic pause; the 4-hour orphan recovery still applies.
extension WatchWorkoutManager {
    var cardioInactivity: WatchCardioInactivityTracker { WatchCardioInactivityTracker() }

    private var cardioAutoPauseEnabled: Bool {
        UserDefaults.standard.object(forKey: "watch.cardio.autoPause") as? Bool ?? true
    }

    func beginCardioInactivityTracking(type: CardioType, isSwim: Bool, ownsSession: Bool, now: Date = Date()) {
        guard !uiTestMode else { return }
        let profile = WatchCardioInactivityTracker.profile(type: type, isSwim: isSwim,
                                                           gps: gpsEnabled, heartRate: heartRateEnabled)
        cardioAutoPaused = false
        if let record = cardioInactivity.begin(type: type, profile: profile, ownsSession: ownsSession, now: now) {
            armCardioInactivityDeadline(record)
        }
    }

    func endCardioInactivityTracking() {
        cardioInactivityTask?.cancel(); cardioInactivityTask = nil
        cardioInactivity.clear()
        cardioAutoPaused = false
    }

    /// Feed one piece of evidence. Passive traffic must never be passed here.
    func recordCardioEvidence(_ event: CardioEvidenceEvent, now: Date = Date()) {
        guard cardioInactivity.record != nil else { return }
        if cardioInactivity.recordEvidence(event, at: now, enabled: cardioAutoPauseEnabled),
           let record = cardioInactivity.record { armCardioInactivityDeadline(record) }
    }

    /// Only a HealthKit sample with its own timestamp can qualify; relay heartbeats and polls
    /// without a sample time cannot.
    func recordCardioHeartRate(_ bpm: Double, sampleEnd: Date?, now: Date = Date()) {
        guard let sampleEnd else { return }
        recordCardioEvidence(.heartRate(bpm: bpm, sampleAt: sampleEnd, restingHR: nil, maxHR: nil), now: now)
    }

    /// Manual pause/resume for a tracked cardio session. Returns false if untracked.
    func toggleCardioPauseIfTracked(_ s: HKWorkoutSession) -> Bool {
        guard let record = cardioInactivity.record else { return false }
        let now = Date()
        if record.pauseOrigin == nil, s.state == .running || !record.ownsSession {
            if record.ownsSession { s.pause(); elapsedTracker.startPause(now: now) }
            cardioInactivity.recordManualPause(at: now)
            cardioInactivityTask?.cancel(); cardioInactivityTask = nil
        } else if record.pauseOrigin != nil {
            resumeCardioByUser(session: s, ownsSession: record.ownsSession, now: now)
        }
        return true
    }

    /// Explicit user Resume (also from the automatic-pause banner).
    func resumeCardioFromBanner() {
        guard let record = cardioInactivity.record, record.pauseOrigin != nil else { cardioAutoPaused = false; return }
        resumeCardioByUser(session: session, ownsSession: record.ownsSession, now: Date())
    }

    private func resumeCardioByUser(session s: HKWorkoutSession?, ownsSession: Bool, now: Date) {
        guard cardioInactivity.recordResume(at: now, enabled: cardioAutoPauseEnabled) else {
            reconcileCardioInactivity(now: now) // terminal deadline passed: reconciliation ends it
            return
        }
        if ownsSession, s?.state == .paused { s?.resume() }
        if ownsSession { elapsedTracker.resume(now: now) }
        cardioAutoPaused = false
        if let record = cardioInactivity.record { armCardioInactivityDeadline(record) }
    }

    /// Pauses the real `HKWorkoutSession` (only one this cardio owns) exactly once.
    func pauseCardioForInactivity(at deadline: Date) {
        guard let record = cardioInactivity.record, record.pauseOrigin == nil else { return }
        if record.ownsSession {
            if session?.state == .running { session?.pause() }
            elapsedTracker.startPause(now: deadline)
        }
        cardioInactivity.recordAutoPause(at: deadline)
        cardioAutoPaused = true
        WKInterfaceDevice.current().play(.notification)
        if let updated = cardioInactivity.record { armCardioInactivityDeadline(updated) }
    }

    func armCardioInactivityDeadline(_ record: WatchCardioInactivityRecord) {
        cardioInactivityTask?.cancel(); cardioInactivityTask = nil
        guard let deadline = record.nextDeadline() else { return }
        cardioInactivityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.cardioInactivityTask = nil
            self?.reconcileCardioInactivity()
        }
    }

    /// Not activity. Compares `now` with stored evidence/deadlines; safe from any lifecycle hook.
    func reconcileCardioInactivity(now: Date = Date()) {
        guard !uiTestMode, cardioInactivity.record != nil else { return }
        switch cardioInactivity.evaluate(now: now, enabled: cardioAutoPauseEnabled) {
        case .autoPause(let at):
            pauseCardioForInactivity(at: at)
            reconcileCardioInactivity(now: now) // grace may also have elapsed while suspended
        case .autoEnd(let at):
            autoFinishCardioForInactivity(endedAt: at)
        case .none:
            if cardioInactivityTask == nil, let record = cardioInactivity.record { armCardioInactivityDeadline(record) }
        }
    }

    /// Restores cardio ownership after relaunch from the durable record and reconciles it.
    /// Returns true when a record existed.
    @discardableResult
    func restoreCardioInactivity() -> Bool {
        guard let record = cardioInactivity.record else { return false }
        cardioSessionStart = record.startedAt
        cardioOwnsSession = record.ownsSession
        cardioAutoPaused = record.pauseOrigin == .automatic
        if record.pauseOrigin != nil, record.ownsSession { elapsedTracker.startPause(now: record.autoPausedAt ?? record.manualPausedAt ?? Date()) }
        reconcileCardioInactivity()
        return true
    }

    /// HealthKit has no session but a record survived (e.g. system ended it): queue a completion
    /// if the terminal deadline passed, otherwise just drop the stale record.
    func settleOrphanCardioRecord(now: Date = Date()) {
        guard !isActive, let record = cardioInactivity.record else { return }
        if case .autoEnd(let at) = cardioInactivity.evaluate(now: now, enabled: cardioAutoPauseEnabled) {
            cardioSessionStart = record.startedAt
            queueAutoEndedCompletion(record: record, endedAt: at)
        }
        endCardioInactivityTracking()
        cardioSessionStart = nil; cardioOwnsSession = false
    }

    /// Idempotent. Ends at the stored deadline: duration excludes paused time, HR is bounded to
    /// the end of active work, the completion is queued once, the owned `HKWorkoutSession` ends
    /// once (a layered cardio never touches the parent session), and a durable notice is saved.
    func autoFinishCardioForInactivity(endedAt: Date) {
        guard let record = cardioInactivity.record, !cardioInactivityFinishing else { return }
        cardioInactivityFinishing = true
        defer { cardioInactivityFinishing = false }
        cardioInactivityTask?.cancel(); cardioInactivityTask = nil
        queueAutoEndedCompletion(record: record, endedAt: endedAt)
        endCardioInactivityTracking() // clears the record first so a re-entrant call is a no-op
        if record.ownsSession, isActive {
            stopWorkout(save: true, endDate: endedAt)
        } else {
            cardioSessionStart = nil; cardioOwnsSession = false
        }
        let notice = WatchCardioInactivityNotice(type: record.type, endedAt: endedAt)
        cardioInactivity.store.saveNotice(notice)
        cardioInactivityNotice = notice
    }

    private func queueAutoEndedCompletion(record: WatchCardioInactivityRecord, endedAt: Date) {
        let duration = record.activeDuration(endedAt: endedAt)
        let activeEnd = min(endedAt, record.autoPausedAt ?? endedAt)
        let hrBound = max(0, activeEnd.timeIntervalSince(record.startedAt))
        let avg: Double? = hrCount > 0 ? accumulatedHR / Double(hrCount) : nil
        let summary = SavedWorkoutSummary(duration: duration, avgHR: avg, maxHR: maxHeartRate,
                                          distanceMeters: distanceMeters,
                                          hrSamples: hrRecorder.finalSamples(duration: hrBound))
        enqueueCardioCompletion(type: record.type, summary: summary, endedAt: endedAt, ignoringSessionStart: true)
    }

    func dismissCardioInactivityNotice() {
        cardioInactivity.store.saveNotice(nil)
        cardioInactivityNotice = nil
    }
}
