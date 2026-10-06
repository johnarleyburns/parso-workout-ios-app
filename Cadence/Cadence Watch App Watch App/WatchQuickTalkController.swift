import AVFoundation
import Foundation
import Observation
import WatchConnectivity
import WatchKit
import CadenceCore
import CadenceFeatures

/// Watch redesign §6 / decision D-W2 — Quick Talk on the wrist.
///
/// watchOS has no speech recognition API, so the watch records a short clip while you hold Log set
/// (≤10 s), sends it to the iPhone (which transcribes with SpeechAnalyzer and deletes it), and turns
/// the text into an outcome with the shared `WatchQuickTalkPlanner`: an exact set log saves now
/// with Undo (D4); anything else is reviewed. With the iPhone away, Talk becomes the system
/// dictation field and the same planner runs on its text. Nothing listens unless asked.
@MainActor
@Observable
final class WatchQuickTalkController {
    enum Phase: Equatable {
        case idle
        case needsPermission
        case listening(startedAt: Date)
        case transcribing(WatchQuickTalkSource)
        case saved(summary: String, undoUntil: Date)
        case review(heard: String, items: [WatchQuickTalkItem])
        case notUnderstood(heard: String, clarification: String?)
        case failed(code: String)
    }

    private(set) var phase: Phase = .idle
    private(set) var level: Float = 0
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTask: Task<Void, Never>?
    private var replyTimeoutTask: Task<Void, Never>?
    private var undoSetID: UUID?
    private weak var model: WatchStrengthFlowModel?
    private var unit: MeasurementUnitPreference = .kilograms

    var isPhoneReachable: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isReachable
    }

    func bind(model: WatchStrengthFlowModel, unit: MeasurementUnitPreference) {
        self.model = model
        self.unit = unit
    }

    // MARK: - Capture (V1)

    func startListening() {
        guard case .idle = phase else { return }
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            phase = .needsPermission
            return
        case .denied:
            phase = .failed(code: "micDenied")
            return
        default:
            break
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("quicktalk-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 24_000
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: WatchQuickTalkPlanner.maximumRecording) else {
                phase = .failed(code: "recorderDidNotStart")
                return
            }
            self.recorder = recorder
            recordingURL = url
            WKInterfaceDevice.current().play(.start)
            phase = .listening(startedAt: Date())
            meterTask = Task { @MainActor [weak self] in
                while let self, case .listening(let start) = self.phase {
                    self.recorder?.updateMeters()
                    self.level = max(0, (self.recorder?.averagePower(forChannel: 0) ?? -60) + 60) / 60
                    if Date().timeIntervalSince(start) >= WatchQuickTalkPlanner.maximumRecording {
                        self.finishListening()
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
        } catch {
            let ns = error as NSError
            phase = .failed(code: "record-\(ns.domain)-\(ns.code)")
        }
    }

    /// Release: stop recording and send the clip to the iPhone.
    func finishListening() {
        guard case .listening = phase else { return }
        meterTask?.cancel()
        replyTimeoutTask?.cancel()
        replyTimeoutTask = nil
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        WKInterfaceDevice.current().play(.stop)
        guard let url = recordingURL, let data = try? Data(contentsOf: url) else {
            phase = .failed(code: "noRecording")
            return
        }
        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
        guard isPhoneReachable else {
            // Dictation fallback is offered in place of hold-to-talk while the phone is away.
            phase = .failed(code: "iPhoneNotNearby")
            return
        }
        phase = .transcribing(.iPhone)
        let message: [String: Any] = [
            WatchSync.Key.command: WatchSync.Key.transcribeQuickTalk,
            WatchSync.Key.quickTalkAudio: data,
            WatchSync.Key.quickTalkFileExtension: "m4a"
        ]
        WCSession.default.sendMessage(message, replyHandler: { [weak self] reply in
            let transcript = reply[WatchSync.Key.quickTalkTranscript] as? String
            let error = reply[WatchSync.Key.quickTalkError] as? String
            Task { @MainActor in
                self?.replyTimeoutTask?.cancel()
                self?.replyTimeoutTask = nil
                if let transcript { self?.handle(transcript: transcript, source: .iPhone) }
                else { self?.phase = .failed(code: error ?? "noTranscript") }
            }
        }, errorHandler: { [weak self] error in
            let ns = error as NSError
            Task { @MainActor in
                self?.replyTimeoutTask?.cancel()
                self?.replyTimeoutTask = nil
                self?.phase = .failed(code: "wc-\(ns.code)")
            }
        })
        // sendMessage has no reply timeout. Without our own deadline the watch
        // can remain on “Connecting to iPhone…” forever after a phone wake or
        // SpeechAnalyzer failure.
        replyTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self,
                  case .transcribing(.iPhone) = self.phase else { return }
            self.phase = .failed(code: "phoneReplyTimedOut")
        }
    }

    /// Slide off the button: discard the clip, nothing is sent.
    func cancelListening() {
        meterTask?.cancel()
        replyTimeoutTask?.cancel()
        replyTimeoutTask = nil
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        phase = .idle
    }

    func requestPermission() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in self?.phase = granted ? .idle : .failed(code: "micDenied") }
        }
    }

    // MARK: - Outcome (V2–V5)

    /// Text from the iPhone or from system dictation (C fallback).
    func handle(transcript: String, source: WatchQuickTalkSource) {
        guard let model else { return }
        let context = WatchQuickTalkPlanner.Context(
            unit: unit,
            currentExercise: model.currentExerciseName,
            exercises: model.exerciseList.map(\.exercise.name),
            performers: model.partners.map(\.name),
            activePerformer: model.performerLabel)
        let outcome = WatchQuickTalkPlanner.outcome(for: transcript, context: context)
        switch outcome {
        case .apply(let action, let summary):
            WatchHeardLogStore.append(HeardVoiceEntry(transcript: transcript, confidence: .exact, appliedAutomatically: true))
            if apply(action) {
                WKInterfaceDevice.current().play(.success)
                phase = .saved(summary: summary, undoUntil: QuickTalkFollowUpWindow(startedAt: Date()).expiresAt)
            } else {
                phase = .failed(code: "applyFailed")
            }
        case .review(let items):
            WatchHeardLogStore.append(HeardVoiceEntry(transcript: transcript, confidence: .inferred, appliedAutomatically: false))
            phase = .review(heard: transcript, items: items)
        case .notUnderstood(let clarification):
            WatchHeardLogStore.append(HeardVoiceEntry(transcript: transcript, confidence: .ambiguous, appliedAutomatically: false))
            phase = .notUnderstood(heard: transcript, clarification: clarification)
        }
        _ = source
    }

    /// Review card: apply the ticked lines in order.
    func confirm(_ items: [WatchQuickTalkItem]) {
        var applied = false
        for item in items { applied = apply(item.action) || applied }
        if applied { WKInterfaceDevice.current().play(.success) }
        phase = .idle
    }

    func undo() {
        if let id = undoSetID, let payload = model?.deleteSet(id: id) {
            WatchSyncSender.send(payload)
        }
        undoSetID = nil
        phase = .idle
    }

    func dismiss() { phase = .idle }

    // MARK: - Applying actions to the workout

    @discardableResult
    private func apply(_ action: VoiceResolvedAction) -> Bool {
        guard let model else { return false }
        switch action {
        case let .logSet(exercise, weightKg, reps, rpe, isWarmup, performer):
            guard let target = model.plannedExercise(named: exercise.name) else { return false }
            model.selectPerformer(named: performer.isOwner ? nil : performer.name)
            model.startLogSet(for: target)
            if let weightKg { model.currentWeight = weightKg }
            model.currentReps = Double(reps)
            if let rpe { model.effortMode = .rpe; model.effortValue = rpe }
            if isWarmup != model.isWarmupSet { model.toggleWarmup() }
            guard let set = model.logSet() else { return false }
            undoSetID = set.id
            if let payload = model.lastSyncPayload { WatchSyncSender.send(payload) }
            return true
        case let .repeatLastSet(exercise, performer, adjustKg):
            guard let target = model.plannedExercise(named: exercise.name) else { return false }
            model.selectPerformer(named: performer.isOwner ? nil : performer.name)
            model.startLogSet(for: target)
            if let adjustKg { model.currentWeight += adjustKg }
            guard let set = model.logSet() else { return false }
            undoSetID = set.id
            if let payload = model.lastSyncPayload { WatchSyncSender.send(payload) }
            return true
        case let .adjustNext(exercise, deltaKg):
            guard let target = model.plannedExercise(named: exercise.name) else { return false }
            model.startLogSet(for: target)
            model.currentWeight += deltaKg
            return true
        case .addExercise(let name):
            model.addExercise(named: name)
            return true
        case .switchExercise(let name):
            guard let target = model.plannedExercise(named: name) else { model.addExercise(named: name); return true }
            model.startLogSet(for: target)
            return true
        case .setPerformer(let performer):
            model.selectPerformer(named: performer.isOwner ? nil : performer.name)
            return true
        case .addPartner(let name):
            model.addPartner(named: name)
            return true
        case .rest(let seconds):
            if let seconds { model.startRest(seconds: seconds) }
            return true
        case .skipRest:
            model.finishRest()
            return true
        case .undo:
            if let id = model.lastLoggedSetID, let payload = model.deleteSet(id: id) { WatchSyncSender.send(payload) }
            return true
        case .pause, .resume:
            NotificationCenter.default.post(name: .watchQuickTalkTogglePause, object: nil)
            return true
        case .finishWorkout:
            NotificationCenter.default.post(name: .watchQuickTalkFinish, object: nil)
            return true
        case .startWorkout:
            return false
        }
    }
}

extension Notification.Name {
    static let watchQuickTalkTogglePause = Notification.Name("watch.quickTalk.togglePause")
    static let watchQuickTalkFinish = Notification.Name("watch.quickTalk.finish")
}

/// One place that hands a flow payload to WatchConnectivity (durable user-info transfer).
enum WatchSyncSender {
    /// Payloads created while WatchConnectivity isn't activated yet (cold launch, no iPhone paired
    /// yet). They used to be dropped; now they wait here, survive relaunch, and go on activation.
    private static let outboxKey = "watch.sync.outbox"

    static func send(_ payload: [String: Any]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            var outbox = UserDefaults.standard.array(forKey: outboxKey) as? [[String: Any]] ?? []
            outbox.append(payload)
            UserDefaults.standard.set(outbox, forKey: outboxKey)
            return
        }
        WCSession.default.transferUserInfo(payload)
    }

    /// Called when the session activates: hands every waiting payload to WatchConnectivity in order.
    static func flushOutbox() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let outbox = UserDefaults.standard.array(forKey: outboxKey) as? [[String: Any]], !outbox.isEmpty
        else { return }
        UserDefaults.standard.removeObject(forKey: outboxKey)
        for payload in outbox { WCSession.default.transferUserInfo(payload) }
    }

    /// Transfers not yet delivered to the phone (F2 receipts): WatchConnectivity's queue plus the outbox.
    static var pendingTransfers: Int {
        let waiting = (UserDefaults.standard.array(forKey: outboxKey) as? [[String: Any]])?.count ?? 0
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return waiting }
        return waiting + WCSession.default.outstandingUserInfoTransfers.count
    }
}
