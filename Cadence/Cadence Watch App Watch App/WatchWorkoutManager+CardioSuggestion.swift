import Foundation
import CadenceFeatures
import CadenceWorkoutFeatures

extension WatchWorkoutManager {
    private static let cardioSuggestionDefaultsKey = "watch.cardioSuggestion.envelope.v1"

    /// Restores the durable cardio envelope (offline relaunch).
    func restoreCardioSuggestion() {
        guard let data = UserDefaults.standard.data(forKey: Self.cardioSuggestionDefaultsKey),
              case .success(let envelope) = WatchCardioSuggestionEnvelope.decode(data) else { return }
        cardioSuggestionEnvelope = envelope
    }

    /// Applies the phone's cardio payload: a valid envelope replaces, an absent key removes,
    /// a malformed payload never replaces a good snapshot.
    func applyCardioSuggestion(context: [String: Any]) {
        switch WatchCardioSuggestionPayload(context: context) {
        case .envelope(let envelope):
            if let data = try? envelope.encoded() {
                UserDefaults.standard.set(data, forKey: Self.cardioSuggestionDefaultsKey)
            }
            cardioSuggestionEnvelope = envelope
        case .absent:
            UserDefaults.standard.removeObject(forKey: Self.cardioSuggestionDefaultsKey)
            cardioSuggestionEnvelope = nil
        case .invalid:
            break
        }
    }
}
