import Foundation
import SwiftData
import CadenceCore
import CadenceFeatures

/// Live objects the coordinator's finalizer needs for one phone cardio session. These stay
/// in memory (like the recorder); only accounting metadata is persisted by the coordinator.
@MainActor
final class PhoneCardioContext {
    let recorder: CardioRecorder?
    let customTitle: String?
    let goalMeters: Double?
    /// Swim only: kept current by the swim view.
    var laps = 0
    var targetLaps = 20
    init(recorder: CardioRecorder?, customTitle: String? = nil, goalMeters: Double? = nil) {
        self.recorder = recorder; self.customTitle = customTitle; self.goalMeters = goalMeters
    }
}

/// Shown (once) when a workout ended automatically for inactivity.
struct AutoEndedCardio {
    let sessionID: UUID
    let workout: CardioWorkout
    let endedAt: Date
}

extension AppModel: PhoneCardioLifecycleActions {
    static let autoPausedMessage = String(localized: "Paused automatically because no activity was detected")

    /// Registers a live phone recorder with the durable coordinator. Returns its session id.
    @discardableResult
    func beginPhoneCardio(type: CardioType, route: String, start: Date, profile: CardioSensorProfile,
                          autoPauseEnabled: Bool, context: PhoneCardioContext) -> UUID {
        phoneCardio.actions = self
        // Adopt the identity reserved when Watch HR was requested (route already registered).
        var sessionID = UUID()
        if let reserved = watchPreflightReservation?.phoneWorkoutSessionID,
           WatchHeartRateRouteStore().route(for: reserved) != nil {
            sessionID = reserved
            var ledger = watchPreflightLedger
            _ = ledger.adopt(sessionID: reserved, start: start, end: Date())
            watchPreflightLedger = ledger
        }
        let session = PhoneLiveCardioSession(id: sessionID, type: type, route: route, start: start,
                                             sensorProfile: profile, autoPauseEnabled: autoPauseEnabled)
        phoneCardioContexts = [session.id: context]
        phoneCardioLastBPM = nil
        autoEndedCardio = nil
        phoneCardio.attach(session: session)
        syncPhoneCardioLiveActivity()
        return session.id
    }

    /// Drops the session after an explicit End/Cancel (never after minimize).
    func endPhoneCardio(_ id: UUID) {
        guard phoneCardio.session?.id == id else { return }
        phoneCardioContexts[id] = nil
        phoneCardio.detachTerminalSession()
        WorkoutLiveActivityCoordinator.shared.end()
    }

    /// Starts/updates the Live Activity while a phone cardio session is live. Teardown is
    /// explicit (`endPhoneCardio`, `finalizePhoneCardio`) and goes through the idempotent
    /// `endAllStale`, so a strength Live Activity is never ended from here.
    func syncPhoneCardioLiveActivity() {
        guard PhoneCardioLiveActivityContent.isLive(phoneCardio.session), let session = phoneCardio.session else { return }
        let content = PhoneCardioLiveActivityContent(session: session, now: Date())
        WorkoutLiveActivityCoordinator.shared.startCardio(content)
        WorkoutLiveActivityCoordinator.shared.updateCardio(content)
    }

    /// Reconcile first; foregrounding/timer ticks are never activity. Called by the root
    /// scene hook, the bounded heartbeat, parked restore, and live cardio views.
    func reconcilePhoneCardio() async {
        phoneCardio.actions = self
        await phoneCardio.reconcile(now: Date())
        syncPhoneCardioLiveActivity()
    }

    /// GPS distance progress and HR evidence. Callers pass raw values; the coordinator
    /// decides what qualifies (steps < 10 m, stale/low/replayed HR are rejected).
    func feedPhoneCardioEvidence(distanceMeters: Double?, bpm: Double?) {
        let now = Date()
        if let distanceMeters { phoneCardio.recordEvidence(.distance(totalMeters: distanceMeters), at: now) }
        // HR counts only when the value changed since the last look (a frozen reading from
        // a lost strap is not a fresh sample); receipt alone is never activity.
        if let bpm, bpm > 0, bpm != phoneCardioLastBPM {
            phoneCardio.recordEvidence(.heartRate(bpm: bpm, sampleAt: now, restingHR: nil, maxHR: nil), at: now)
        }
        phoneCardioLastBPM = bpm
    }

    func phoneCardioUserAction() { phoneCardio.recordEvidence(.userAction, at: Date()) }

    func phoneCardioManualPause(_ id: UUID) {
        guard phoneCardio.session?.id == id else { return }
        phoneCardio.recordManualPause(at: Date())
    }

    /// Whether a user resume is allowed. True when no coordinator session tracks `id`.
    func phoneCardioMayResume(_ id: UUID?) -> Bool {
        guard let id, let s = phoneCardio.session, s.id == id else { return true }
        if s.receipt != nil { return false }
        if !s.isPaused { return true }
        return phoneCardio.recordResume(at: Date())
    }

    /// The automatic pause timestamp for `id`, when the coordinator paused it.
    func phoneCardioAutoPausedAt(_ id: UUID?) -> Date? {
        guard let id, let s = phoneCardio.session, s.id == id,
              s.inactivity.pauseOrigin == .automatic else { return nil }
        return s.inactivity.pausedAt
    }

    /// The auto-ended workout for `id`, consumed by the view that was showing it.
    func claimAutoEnded(_ id: UUID?) -> CardioWorkout? {
        guard let id, let e = autoEndedCardio, e.sessionID == id else { return nil }
        autoEndedCardio = nil
        phoneCardio.detachTerminalSession()
        return e.workout
    }

    func dismissAutoEndedNotice() {
        autoEndedCardio = nil
        phoneCardio.detachTerminalSession()
    }

    // MARK: PhoneCardioLifecycleActions

    func pauseForInactivity(session: PhoneLiveCardioSession, at: Date) {
        // Recorder pause only: the Watch HR session and GPS remain owned until the
        // workout is resumed or finalized, so a resume never loses its sensors.
        phoneCardioContexts[session.id]?.recorder?.pause()
    }

    func finalizePhoneCardio(sessionID: UUID, endedAt: Date, reason: PhoneCardioFinalizeReason) async {
        guard let container = phoneCardioModelContainer, let session = phoneCardio.session, session.id == sessionID,
              let ctx = phoneCardioContexts[sessionID] else {
            // Nothing live to finalize (relaunch lost the in-memory recorder): clear parked state.
            parkedCardio.clear()
            return
        }
        let modelContext = ModelContext(container)
        let existing = (try? modelContext.fetch(FetchDescriptor<CardioWorkout>(
            predicate: #Predicate { $0.id == sessionID })))?.first
        stopWatchWorkout()
        let active = session.activeDuration(endedAt: endedAt)
        var saved = existing
        if saved == nil {
            let profile: CardioIntensityProfile
            if let settings = phoneCardioSettings {
                profile = await cardioIntensityProfile(model: self, settings: settings)
            } else {
                profile = .ageEstimated(age: 35)
            }
            if session.route == "swim" {
                let end = session.start.addingTimeInterval(active)
                saved = try? WorkoutRepository.saveSwim(
                    id: sessionID, start: session.start, end: end, laps: ctx.laps,
                    targetLaps: ctx.targetLaps, intensityProfile: profile,
                    intensitySummary: CardioMinuteAccumulator.summarize(duration: active, samples: [], profile: profile),
                    metEstimate: METEstimator.cardio(type: .swim, duration: active),
                    in: modelContext)
            } else if let recorder = ctx.recorder {
                var summary = recorder.end(at: endedAt)
                summary.id = sessionID
                summary.customTitle = ctx.customTitle
                summary.targetDistanceMeters = ctx.goalMeters
                summary.intensityProfile = profile
                summary.intensitySummary = CardioMinuteAccumulator.summarize(
                    duration: active, samples: summary.hrSamples, profile: profile)
                summary.metEstimate = METEstimator.cardio(type: summary.type, duration: active)
                saved = try? WorkoutRepository.saveRecordedCardio(
                    summary, source: .iphone, healthKitWorkoutUUID: nil, in: modelContext)
            }
            if let saved {
                let report = await healthBackup.enqueueAndDrain(cardio: saved)
                if let hkID = report.savedObjectIDs[saved.id] {
                    saved.healthKitWorkoutUUID = hkID
                    try? modelContext.save()
                }
            }
        } else {
            _ = ctx.recorder?.end(at: endedAt) // idempotent stop of GPS
        }
        parkedCardio.clear()
        phoneCardioContexts[sessionID] = nil
        if let saved { autoEndedCardio = AutoEndedCardio(sessionID: sessionID, workout: saved, endedAt: endedAt) }
        WorkoutLiveActivityCoordinator.shared.end()
    }
}

extension AppModel {
    /// True while the coordinator holds the live session in an automatic pause.
    var phoneCardioAutoPaused: Bool {
        phoneCardio.session?.inactivity.pauseOrigin == .automatic && phoneCardio.session?.receipt == nil
    }
}
