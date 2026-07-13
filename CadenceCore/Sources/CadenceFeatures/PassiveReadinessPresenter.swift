import Foundation
import CadenceCore

/// Prepares the Home Coach card's passive-readiness line for rendering. Pure and
/// headless — no SwiftUI — so the copy and the citation wiring are `swift test`-
/// verifiable. The view maps this to text + `CitationLink`s.
///
/// D4: this NEVER contradicts a fresh self-report. It only produces a line when the
/// fused signal carries a passive claim (or asks for a check-in); the fusion has
/// already let self-report win where present.
public enum PassiveReadinessPresenter {

    public struct Display: Equatable {
        /// The headline sentence, e.g. "HRV 18% below your baseline, 5h 10m sleep."
        public let message: String
        /// Whether to render a "20 seconds to tell the coach how you feel?" prompt.
        public let promptCheckIn: Bool
        /// Citation IDs to resolve + render as tappable links. Never empty when a
        /// claim is shown (HARD RULE).
        public let citationIds: [String]

        public init(message: String, promptCheckIn: Bool, citationIds: [String]) {
            self.message = message
            self.promptCheckIn = promptCheckIn
            self.citationIds = citationIds
        }
    }

    /// Returns the display, or `nil` when there is nothing honest to say (no passive
    /// claim and no prompt).
    public static func display(for readiness: ReadinessSnapshot?) -> Display? {
        guard let readiness, let passive = readiness.passive, passive.makesClaim else {
            return nil
        }
        guard !passive.citationIds.isEmpty else { return nil }  // HARD RULE guard

        let message = sentence(for: passive)
        return Display(message: message,
                       promptCheckIn: readiness.promptCheckIn,
                       citationIds: passive.citationIds)
    }

    static func sentence(for passive: PassiveReadinessSignal) -> String {
        var parts: [String] = []
        if let hrv = passive.hrvDeviationPct, hrv <= -1 {
            parts.append("HRV \(Int(hrv.rounded())) percent below your baseline")
        }
        if let rhr = passive.restingHRDeltaBpm, rhr >= 1 {
            parts.append("resting HR up \(Int(rhr.rounded())) bpm")
        }
        if let debt = passive.sleepDebtHours, debt >= 0.5 {
            parts.append(String(format: "sleep down %.1fh vs your average", debt))
        }

        let lead: String
        switch passive.level {
        case .stronglySuppressed: lead = "Recovery looks well below your baseline"
        case .suppressed: lead = "Recovery looks a bit below your baseline"
        default: lead = "Recovery"
        }

        guard !parts.isEmpty else { return "\(lead)." }
        return "\(lead): \(parts.joined(separator: ", "))."
    }
}
