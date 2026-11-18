import CadenceFeatures
import Foundation
import CadenceCore

/// Watch redesign §5 I1 — an interval phase is colour **and** word: red Work, green Rest, amber in
/// the last seconds of work, blue for warm-up/cool-down. The view maps the tone to colours; this
/// keeps the mapping (and its accessibility word) testable without SwiftUI.
public enum WatchIntervalPhaseTone: String, Equatable, Sendable {
    case work, ending, rest, easy

    public static func tone(for state: FullScreenColorState) -> WatchIntervalPhaseTone {
        switch state {
        case .work: .work
        case .warning, .imminent: .ending
        case .rest: .rest
        case .neutral: .easy
        }
    }
}

/// Watch redesign §5 I2 — the plan's target under the steady-cardio metrics ("Planned: 30 min ·
/// Zone 2"), or nil when nothing was planned.
public enum WatchCardioPlanTarget {
    public static func text(durationSeconds: Int?, zone: Int?) -> String? {
        var parts: [String] = []
        if let durationSeconds, durationSeconds > 0 {
            parts.append({
                #if os(Linux)
                "\(max(1, durationSeconds / 60)) min"
                #else
                String(localized: "\(max(1, durationSeconds / 60)) min", bundle: FeatureLocalization.bundle)
                #endif
            }())
        }
        if let zone, (1...5).contains(zone) { parts.append({
            #if os(Linux)
            "Zone \(zone)"
            #else
            String(localized: "Zone \(zone)", bundle: FeatureLocalization.bundle)
            #endif
        }()) }
        guard !parts.isEmpty else { return nil }
        return {
            #if os(Linux)
            "Planned: \(parts.joined(separator: " · "))"
            #else
            String(localized: "Planned: \(parts.joined(separator: " · "))", bundle: FeatureLocalization.bundle)
            #endif
        }()
    }

    /// 0...1 progress towards the planned duration, for the hairline under the target.
    public static func progress(elapsed: TimeInterval, durationSeconds: Int?) -> Double? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        return min(1, max(0, elapsed / Double(durationSeconds)))
    }
}
