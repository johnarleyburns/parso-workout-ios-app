import Foundation

/// Parses a BLE 0x2A37 Heart Rate Measurement payload (8- or 16-bit format).
/// Pulled out of the app's `HeartRateMonitor` (test-pyramid Phase 2) so its
/// bit-format handling is unit-tested headlessly rather than in the simulator.
public enum HeartRateParser {
    public static func parse(_ data: Data) -> Double? {
        guard let flags = data.first else { return nil }
        let is16Bit = (flags & 0x01) != 0
        if is16Bit {
            guard data.count >= 3 else { return nil }
            let value = UInt16(data[1]) | (UInt16(data[2]) << 8)
            return Double(value)
        } else {
            guard data.count >= 2 else { return nil }
            return Double(data[1])
        }
    }
}
