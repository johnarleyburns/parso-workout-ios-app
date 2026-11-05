import Foundation

/// Display strings for the Watch live heart-rate readout. Shared by the Heart
/// page and the warm-up/cool-down badge so rounding stays consistent.
public struct LiveHeartRateDisplay: Equatable, Sendable {
    public let bpm: Int?

    public init(bpm: Double?) {
        if let bpm, bpm.isFinite, bpm > 0 {
            self.bpm = Int(bpm.rounded())
        } else {
            self.bpm = nil
        }
    }

    /// Bare number, or "--" before the first sample.
    public var valueText: String { bpm.map(String.init) ?? "--" }
    public var hasSample: Bool { bpm != nil }
}
