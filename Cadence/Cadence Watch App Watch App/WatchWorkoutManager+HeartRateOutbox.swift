import Foundation
import OSLog
import WatchConnectivity
import CadenceFeatures

// MARK: - Durable heart-rate delivery
//
// `sendMessage` stays the low-latency display path (see HeartRatePolling).
// The authoritative path is `WatchHeartRateOutbox`: every real, timestamped
// reading is persisted, then delivered by `sendMessage` (when reachable) and
// `transferUserInfo`, and kept until the phone acknowledges it.

/// WatchConnectivity adapter for the outbox.
struct WatchWCHeartRateTransport: WatchHeartRateTransport {
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    var isActivated: Bool { session?.activationState == .activated }
    var isReachable: Bool { session?.isReachable ?? false }
    func sendImmediate(_ message: WatchHRMessage) {
        session?.sendMessage(message.payload, replyHandler: nil, errorHandler: nil)
    }
    func transferUserInfo(_ message: WatchHRMessage) {
        _ = session?.transferUserInfo(message.payload)
    }
}

/// Read-only view of the retired UserDefaults journals (migration source only).
struct WatchOutboxDefaultsLegacyReader: WatchOutboxLegacyReader {
    func data(forKey key: String) -> Data? { UserDefaults.standard.data(forKey: key) }
}

/// File-backed outbox journals (Application Support), one per delivery path.
enum WatchOutboxStores {
    private static func make(file: String, legacyKey: String) -> FileWatchHeartRateOutboxStore {
        let fs = WatchOutboxDirectoryFileSystem.applicationSupport()
            ?? WatchOutboxDirectoryFileSystem(directory: FileManager.default.temporaryDirectory)
        return FileWatchHeartRateOutboxStore(fileSystem: fs, legacy: WatchOutboxDefaultsLegacyReader(),
                                             fileName: file, legacyKey: legacyKey)
    }
    static func heartRate() -> FileWatchHeartRateOutboxStore {
        make(file: FileWatchHeartRateOutboxStore.heartRateFileName, legacyKey: FileWatchHeartRateOutboxStore.heartRateLegacyKey)
    }
    static func strengthCompletion() -> FileWatchHeartRateOutboxStore {
        make(file: FileWatchHeartRateOutboxStore.strengthCompletionFileName,
             legacyKey: FileWatchHeartRateOutboxStore.strengthCompletionLegacyKey)
    }
}

extension WatchWorkoutManager {
    static let phoneWorkoutSessionIDKey = "watch.activeWorkout.phoneWorkoutSessionID"
    static let phoneCaptureEpochKey = "watch.activeWorkout.phoneCaptureEpoch"
    private static let outboxFlushGap: TimeInterval = 10
    private static let log = Logger(subsystem: "guru.parso.cadence", category: "WatchHRDelivery")

    /// Pairs the phone's workout identity with its request ID, persisted with
    /// the active workout metadata and restored on recovery.
    /// The epoch comes from the adopted start command, never from current state;
    /// without one (older phone) no durable journal is bound.
    func bindPhoneWorkoutSession(_ id: UUID?, captureEpoch: UUID? = nil) {
        phoneWorkoutSessionID = id
        phoneCaptureEpoch = id == nil ? nil : captureEpoch
        if let id, let epoch = phoneCaptureEpoch, let request = phoneRequestID.flatMap(UUID.init(uuidString:)) {
            hrOutbox.bind(phoneWorkoutSessionID: id, watchRequestID: request, captureEpoch: epoch)
        }
        if let epoch = phoneCaptureEpoch { UserDefaults.standard.set(epoch.uuidString, forKey: Self.phoneCaptureEpochKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.phoneCaptureEpochKey) }
        if let id { UserDefaults.standard.set(id.uuidString, forKey: Self.phoneWorkoutSessionIDKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.phoneWorkoutSessionIDKey) }
    }

    /// Workout ended: flush, then unpair. The outbox keeps its journal until
    /// the phone acknowledges it or the user explicitly discards.
    func endPhoneWorkoutJournal() {
        if phoneWorkoutSessionID != nil { hrOutbox.flush() }
        bindPhoneWorkoutSession(nil)
    }

    func restorePhoneWorkoutSession() {
        let id = UserDefaults.standard.string(forKey: Self.phoneWorkoutSessionIDKey).flatMap(UUID.init(uuidString:))
        phoneWorkoutSessionID = id
        phoneCaptureEpoch = UserDefaults.standard.string(forKey: Self.phoneCaptureEpochKey).flatMap(UUID.init(uuidString:))
        if let id, let epoch = phoneCaptureEpoch, let request = phoneRequestID.flatMap(UUID.init(uuidString:)) {
            hrOutbox.bind(phoneWorkoutSessionID: id, watchRequestID: request, captureEpoch: epoch)
        }
    }

    /// Journals a real reading (never a heartbeat repeat) and delivers it in
    /// bounded batches.
    func journalHeartRate(_ bpm: Double, sampleEnd: Date?) {
        guard phoneWorkoutSessionID != nil, phoneCaptureEpoch != nil, phoneRequestID != nil else { return }
        let source: HeartRateObservationSource = sampleEnd == nil ? .watchBLE : .watchHealthKit
        hrOutbox.record(bpm: bpm, sampleEnd: sampleEnd ?? Date(), source: source)
        flushHeartRateOutboxIfDue()
    }

    func flushHeartRateOutboxIfDue() {
        let uptime = ProcessInfo.processInfo.systemUptime
        guard uptime - lastOutboxFlushUptime >= Self.outboxFlushGap else { return }
        lastOutboxFlushUptime = uptime
        hrOutbox.flush()
    }

    /// Re-attempts unacknowledged data after activation/reachability recovery.
    func retryHeartRateOutbox(reason: String) {
        hrOutbox.retry(reason: reason)
        strengthCompletionOutbox.retry(reason: reason)
    }

    /// Handles a protocol message from the phone (finalize request or ack).
    func handleHeartRateProtocol(_ message: [String: Any]) -> [String: Any] {
        switch WatchHRMessage.parse(message) {
        case .failure(let reason):
            Self.log.error("rejected: \(reason.rawValue, privacy: .public)")
            return ["ack": false]
        case .success(let parsed):
            switch parsed.kind {
            case .finalizeRequest: return ["ack": hrOutbox.handleFinalizeRequest(parsed)]
            case .observations, .finalizeAcknowledgement:
                guard parsed.acknowledgement != nil else { return ["ack": false] }
                let phoneStarted = hrOutbox.handleAcknowledgement(parsed)
                return ["ack": strengthCompletionOutbox.handleAcknowledgement(parsed) || phoneStarted]
            }
        }
    }
}
