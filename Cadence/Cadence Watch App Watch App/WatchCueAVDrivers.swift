import AVFoundation
import CadenceFeatures

/// AVSpeechSynthesizer adapter. Speech uses the app session so the coordinator's lease
/// is the only thing keeping it active. Delegate callbacks carry only an object identity,
/// which is mapped to the request ID on the main actor.
@MainActor
final class WatchAVSpeechDriver: NSObject, WatchCueSpeechDriving, AVSpeechSynthesizerDelegate {
    var onEvent: (@MainActor @Sendable (WatchSpeechEvent) -> Void)?
    private var synthesizer = AVSpeechSynthesizer()
    private var utterances: [ObjectIdentifier: (id: UUID, utterance: AVSpeechUtterance)] = [:]

    var synthesizerUsesApplicationAudioSession: Bool { synthesizer.usesApplicationAudioSession }

    override init() {
        super.init()
        configure()
    }

    private func configure() {
        synthesizer.usesApplicationAudioSession = true
        synthesizer.delegate = self
    }

    func enqueue(id: UUID, text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.volume = 1
        utterance.prefersAssistiveTechnologySettings = true
        if let voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US") {
            utterance.voice = voice
        }
        utterances[ObjectIdentifier(utterance)] = (id, utterance)
        synthesizer.speak(utterance)
    }

    func cancel(id: UUID) {
        guard let key = utterances.first(where: { $0.value.id == id })?.key else { return }
        utterances.removeValue(forKey: key)
        // Only stop when this request is still known to the synthesizer; stopping an idle
        // synthesizer immediately before speaking drops the new utterance on watchOS.
        synthesizer.stopSpeaking(at: .immediate)
    }

    func reset() {
        utterances.removeAll()
        synthesizer.delegate = nil
        synthesizer = AVSpeechSynthesizer()
        configure()
    }

    private func deliver(_ key: ObjectIdentifier, finish: Bool) {
        guard let entry = utterances[key] else { return }
        if finish { utterances.removeValue(forKey: key) }
        onEvent?(finish ? .finished(entry.id) : .started(entry.id))
    }

    private func deliverCancel(_ key: ObjectIdentifier) {
        // A cancel() already removed the mapping, so a late callback is ignored.
        guard let entry = utterances.removeValue(forKey: key) else { return }
        onEvent?(.cancelled(entry.id))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.deliver(key, finish: false) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.deliver(key, finish: true) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.deliverCancel(key) }
    }
}

/// Distinct AVAudioPlayer + delegate proxy per playback, so an old callback can never be
/// mistaken for a new strike.
@MainActor
final class WatchAVBellDriver: WatchCueBellDriving {
    var onEvent: (@MainActor @Sendable (WatchBellEvent) -> Void)?
    private var players: [UUID: (player: AVAudioPlayer, proxy: BellProxy)] = [:]

    private final class BellProxy: NSObject, AVAudioPlayerDelegate, Sendable {
        let id: UUID
        let deliver: @Sendable (WatchBellEvent) -> Void
        init(id: UUID, deliver: @escaping @Sendable (WatchBellEvent) -> Void) {
            self.id = id
            self.deliver = deliver
        }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            deliver(flag ? .finished(id) : .failed(id))
        }
        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            deliver(.failed(id))
        }
    }

    func start(id: UUID, kind: WatchBellKind) -> Bool {
        let name = kind == .phase ? "opening-closing-bell" : "warning-bell"
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        let proxy = BellProxy(id: id) { [weak self] event in
            Task { @MainActor in self?.onEvent?(event) }
        }
        player.delegate = proxy
        players[id] = (player, proxy)
        // Preparation happens here, after the caller holds a lease.
        player.prepareToPlay()
        guard player.play() else {
            players.removeValue(forKey: id)
            return false
        }
        return true
    }

    func stop(id: UUID) {
        players.removeValue(forKey: id)?.player.stop()
    }
}
