import Foundation
import HealthKit
import CadenceFeatures

// MARK: - Heart rate to the phone
//
// A phone-started workout streams heart rate to the iPhone over
// WatchConnectivity. It keeps working with the screen off only because the
// app runs as a background workout (`WKBackgroundModes` → `workout-processing`,
// checked by scripts/check-watch-background-modes.sh); while a workout runs in
// the background the session stays reachable and each message wakes the phone.
//
// Cadence (`WatchHRRelaySchedule`): every new reading is sent when it
// arrives, at most once a second; with nothing new, the last value is resent
// every 5 s as a heartbeat. One one-shot timer covers both, so nothing runs
// between readings, which keeps the background workout well clear of the
// CPU use watchOS suspends apps for.

extension WatchWorkoutManager {
    private var uptimeNow: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// A heart-rate reading from HealthKit (`sampleEnd` is the end of its
    /// sample) or from a Bluetooth strap (`nil`). Sends it to the phone unless
    /// it was already handled.
    func relayReading(_ bpm: Double, endingAt sampleEnd: Date?) {
        guard phoneRequestID != nil,
              relaySchedule.observeReading(endingAt: sampleEnd, uptime: uptimeNow) else { return }
        sendHeartRateToPhoneSoon()
    }

    /// Sends the latest value now, or as soon as the minimum gap allows.
    /// Also used when the phone becomes reachable again after a blip.
    func sendHeartRateToPhoneSoon() {
        guard phoneRequestID != nil else { return }
        let wait = relaySchedule.delayBeforeSending(uptime: uptimeNow)
        if wait > 0 {
            scheduleHeartRateRelay(after: wait)
        } else {
            sendHeartRateToPhone()
        }
    }

    /// Sends `currentBPM`, then arms the heartbeat. An unreachable phone skips
    /// this send; the heartbeat retries. With no new reading for longer than
    /// the phone's stale window the last value is not resent, so a lost
    /// sensor shows as stale on the phone instead of a frozen live value.
    private func sendHeartRateToPhone() {
        defer { scheduleHeartRateRelay(after: WatchHRRelaySchedule.heartbeatInterval) }
        guard !relaySchedule.isNewestReadingStale(uptime: uptimeNow) else { return }
        guard let bpm = currentBPM, bpm > 0,
              let requestID = phoneRequestID,
              let session = wcSession, session.isReachable else { return }
        session.sendMessage(["bpm": bpm, "active": true, "requestID": requestID], replyHandler: nil, errorHandler: nil)
        relaySchedule.recordSend(uptime: uptimeNow)
    }

    /// Replaces the pending relay timer. One timer at a time: either a reading
    /// waiting out the minimum gap, or the next heartbeat.
    private func scheduleHeartRateRelay(after delay: TimeInterval) {
        relayTimer?.invalidate()
        relayTimer = nil
        guard isActive || isMonitoring, phoneRequestID != nil else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.heartRateRelayTimerFired() }
        }
        // Lets watchOS batch this wake-up with others.
        timer.tolerance = delay >= WatchHRRelaySchedule.heartbeatInterval ? 0.5 : 0.1
        relayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func heartRateRelayTimerFired() {
        relayTimer = nil
        guard isActive || isMonitoring else { return }
        // Picks up a reading whose builder callback has not arrived yet, so the
        // phone never waits on a delayed callback for longer than a heartbeat.
        refreshHeartRateFromBuilder()
        sendHeartRateToPhone()
    }

    func stopHeartRateRelay() {
        relayTimer?.invalidate()
        relayTimer = nil
        relaySchedule.reset()
    }

    // MARK: - Watch display refresh

    /// Refreshes the Watch's own heart-rate display every second while the
    /// app is active. It pauses when the app resigns active (wrist down, screen
    /// off or dimmed, another app); a dimmed Always-On screen still updates
    /// from each new reading, which arrives about as often as the poll would
    /// find one. The relay above does not depend on it.
    func startHeartRatePolling() {
        hrPollTimer?.invalidate()
        hrPollTimer = nil
        guard displayActive else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollHeartRate() }
        }
        timer.tolerance = 0.2
        hrPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Called by the app delegate as the app becomes active (screen on, app in
    /// front) or resigns active (wrist down, screen off, another app).
    func setDisplayActive(_ active: Bool) {
        displayActive = active
        if active {
            if isActive || isMonitoring { startHeartRatePolling() }
        } else {
            hrPollTimer?.invalidate()
            hrPollTimer = nil
        }
    }

    #if DEBUG
    var isHeartRatePollingForTesting: Bool { hrPollTimer?.isValid == true }
    var isHeartRateRelayArmedForTesting: Bool { relayTimer?.isValid == true }
    #endif

    fileprivate func pollHeartRate() {
        guard isActive || isMonitoring, let reading = latestBuilderHeartRate() else { return }
        applyPolledHeartRate(reading.bpm, sampleEnd: reading.sampleEnd)
    }

    /// Updates the displayed value from the builder without relaying it; the
    /// caller sends.
    private func refreshHeartRateFromBuilder() {
        guard hrSource == .appleWatch, let reading = latestBuilderHeartRate(),
              relaySchedule.observeReading(endingAt: reading.sampleEnd, uptime: uptimeNow) else { return }
        currentBPM = reading.bpm
    }

    private func latestBuilderHeartRate() -> (bpm: Double, sampleEnd: Date?)? {
        guard let builder,
              let statistics = builder.statistics(for: HKQuantityType(.heartRate)),
              let quantity = statistics.mostRecentQuantity() else { return nil }
        return (quantity.doubleValue(for: HKUnit(from: "count/min")),
                statistics.mostRecentQuantityDateInterval()?.end)
    }
}
