import AVFoundation
import Speech

@MainActor
protocol QuickTalkTranscriptionEngine: AnyObject {
    var onTranscript: ((String) -> Void)? { get set }
    func prepare(format: AVAudioFormat) async throws
    func append(_ buffer: AVAudioPCMBuffer)
    func finish()
}

/// iOS 26's SpeechAnalyzer is the primary phone transcriber. The legacy
/// SFSpeechRecognizer remains a compatibility fallback for older OS builds and
/// for devices without an installed on-device speech asset.
@available(iOS 26.0, *)
@MainActor
final class SpeechAnalyzerTranscriptionEngine: QuickTalkTranscriptionEngine {
    var onTranscript: ((String) -> Void)?
    private let module: DictationTranscriber
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    init(locale: Locale = .current) {
        module = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
    }

    func prepare(format: AVAudioFormat) async throws {
        let stream = AsyncStream<AnalyzerInput> { continuation in
            inputContinuation = continuation
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: format)
        Task { [weak analyzer] in
            guard let analyzer else { return }
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                // The caller will retain the last partial transcript and can
                // still use the compatibility path on the next capture.
            }
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in module.results {
                    onTranscript?(String(result.text.characters))
                }
            } catch { }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        inputContinuation?.yield(AnalyzerInput(buffer: buffer))
    }

    func finish() {
        inputContinuation?.finish()
        inputContinuation = nil
        let analyzer = analyzer
        Task { try? await analyzer?.finalizeAndFinishThroughEndOfInput() }
    }
}
