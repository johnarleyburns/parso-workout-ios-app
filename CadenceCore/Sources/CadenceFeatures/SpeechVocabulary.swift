import Foundation

/// Builds the bounded exercise vocabulary handed to the legacy
/// `SFSpeechAudioBufferRecognitionRequest.contextualStrings`. It only biases
/// recognition; shared post-transcription matching remains the safety net.
public enum SpeechVocabulary {
    /// Small cap so large catalogs are never passed to the recognizer.
    public static let maxCount = 30

    /// Current exercise first, then the remaining names in their given order.
    /// Names are trimmed; empty and duplicate (exact, after trimming) values are dropped.
    public static func exerciseVocabulary(current: String?, exercises: [String],
                                          limit: Int = maxCount) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in [current ?? ""] + exercises {
            guard result.count < limit else { break }
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            result.append(name)
        }
        return result
    }
}

/// Minimal seam so the legacy request configuration is unit-testable without Speech.
public protocol ContextualStringsConfigurable: AnyObject {
    var contextualStrings: [String] { get set }
}

public extension SpeechVocabulary {
    static func apply(_ vocabulary: [String], to request: some ContextualStringsConfigurable) {
        request.contextualStrings = vocabulary
    }
}
