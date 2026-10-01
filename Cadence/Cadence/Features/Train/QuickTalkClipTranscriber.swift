import AVFoundation
import Foundation
import Speech
import CadenceFeatures

/// Watch Quick Talk (decision D-W2): watchOS has no speech recognition API, so the watch records a
/// short clip and the iPhone transcribes it with the same on-device SpeechAnalyzer Quick Talk uses.
/// The clip is written to a temporary file only for the analyzer and deleted right after.
enum QuickTalkClipTranscriber {
    /// Returns the WatchConnectivity reply: the transcript, or an error code the watch shows.
    @MainActor
    static func transcribe(_ audio: Data, fileExtension: String) async -> [String: Any] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quicktalk-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension.isEmpty ? "m4a" : fileExtension)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try audio.write(to: url, options: .atomic)
            let text = try await transcribeFile(url)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return [WatchSync.Key.quickTalkError: "noSpeech"]
            }
            return [WatchSync.Key.quickTalkTranscript: text]
        } catch let error as QuickTalkClipError {
            return [WatchSync.Key.quickTalkError: error.rawValue]
        } catch {
            let ns = error as NSError
            return [WatchSync.Key.quickTalkError: "transcription-\(ns.domain)-\(ns.code)"]
        }
    }

    enum QuickTalkClipError: String, Error {
        case speechAssetsMissing
    }

    private static func transcribeFile(_ url: URL) async throws -> String {
        let transcriber = DictationTranscriber(locale: .current, preset: .shortDictation)
        // The speech model is installed by phone Quick Talk setup; never download it silently here.
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw QuickTalkClipError.speechAssetsMissing
        }
        let file = try AVAudioFile(forReading: url)
        let collector = Task {
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        return try await collector.value
    }
}
