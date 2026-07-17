import Foundation
import Observation
import CadenceCore

/// Pure view-model for the watch-side HR display. Mapped by the watch view to
/// a zone color + label; headless-testable with injected BPM samples.
@Observable
public final class WatchHRProvider {

    public struct State: Equatable, Sendable {
        public var bpm: Double?
        public var zone: Int
        public var zoneLabel: String
        public var zoneFraction: Double // 0...1 for zone bar fill

        public var bpmText: String {
            guard let bpm else { return "--" }
            return String(format: "%.0f", bpm)
        }
    }

    public var state = State(bpm: nil, zone: 0, zoneLabel: "--", zoneFraction: 0)

    public func update(bpm: Double?, maxHR: Double = 0) {
        let effectiveMax = maxHR > 0 ? maxHR : CardioMath.defaultMaxHR(age: 30)
        let zone = bpm.map { CardioMath.hrZone(bpm: $0, maxHR: effectiveMax) } ?? 0
        let label = zoneLabel(for: zone)
        let fraction = bpm.map { fractionInZone(bpm: $0, zone: zone, maxHR: effectiveMax) } ?? 0

        state = State(bpm: bpm, zone: zone, zoneLabel: label, zoneFraction: fraction)
    }

    private func zoneLabel(for zone: Int) -> String {
        switch zone {
        case 1: return "Recovery"
        case 2: return "Endurance"
        case 3: return "Tempo"
        case 4: return "Threshold"
        case 5: return "Max"
        default: return "--"
        }
    }

    private func fractionInZone(bpm: Double, zone: Int, maxHR: Double) -> Double {
        let pct = bpm / maxHR
        switch zone {
        case 1: return pct / 0.60
        case 2: return (pct - 0.60) / 0.10
        case 3: return (pct - 0.70) / 0.10
        case 4: return (pct - 0.80) / 0.10
        case 5: return (pct - 0.90) / 0.10
        default: return 0
        }
    }
}
