import XCTest
@testable import CadenceCore

/// Recorded Watch HR ingestion (feedback batch 4): the pure downsample helper
/// that keeps stored HR curves light.
final class HRSamplingTests: XCTestCase {

    private func series(_ n: Int) -> [HRSamplePoint] {
        (0..<n).map { HRSamplePoint(t: TimeInterval($0), bpm: Double(120 + $0 % 40)) }
    }

    func testSmallSeriesPassesThroughSorted() {
        let unsorted = [HRSamplePoint(t: 2, bpm: 130),
                        HRSamplePoint(t: 0, bpm: 120),
                        HRSamplePoint(t: 1, bpm: 125)]
        let out = HRSampling.downsample(unsorted, maxPoints: 120)
        XCTAssertEqual(out.map(\.t), [0, 1, 2], "returned sorted, unchanged count")
    }

    func testCapsToMaxPoints() {
        let out = HRSampling.downsample(series(5000), maxPoints: 120)
        XCTAssertLessThanOrEqual(out.count, 120)
        XCTAssertGreaterThan(out.count, 1)
    }

    func testKeepsFirstAndLast() {
        let input = series(1000)
        let out = HRSampling.downsample(input, maxPoints: 100)
        XCTAssertEqual(out.first?.t, input.first?.t, "first sample preserved")
        XCTAssertEqual(out.last?.t, input.last?.t, "last sample preserved")
    }

    func testMonotonicTime() {
        let out = HRSampling.downsample(series(2000), maxPoints: 60)
        XCTAssertEqual(out, out.sorted { $0.t < $1.t }, "output stays chronological")
    }
}
