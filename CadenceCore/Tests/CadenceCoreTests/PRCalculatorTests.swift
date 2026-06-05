import XCTest
@testable import CadenceCore

final class PRCalculatorTests: XCTestCase {

    private func s(_ w: Double, _ r: Int, warmup: Bool = false, day: Int = 0) -> SetSample {
        SetSample(weight: w, reps: r, date: Date(timeIntervalSince1970: TimeInterval(day) * 86_400), isWarmup: warmup)
    }

    func testBestTopWeight() {
        let samples = [s(100, 5), s(110, 1), s(105, 3)]
        XCTAssertEqual(PRCalculator.best(samples, rule: .topWeight, formula: .epley), 110)
    }

    func testBestEstimated1RM() {
        // 100x5 → 116.67 ; 110x1 → 110 ; so 100x5 wins on e1RM
        let samples = [s(100, 5), s(110, 1)]
        XCTAssertEqual(PRCalculator.best(samples, rule: .estimated1RM, formula: .epley)!, 116.67, accuracy: 0.01)
    }

    func testBestTopVolume() {
        let samples = [s(100, 5), s(80, 10)] // 500 vs 800
        XCTAssertEqual(PRCalculator.best(samples, rule: .topVolume, formula: .epley), 800)
    }

    func testWarmupsIgnored() {
        let samples = [s(200, 1, warmup: true), s(100, 5)]
        XCTAssertEqual(PRCalculator.best(samples, rule: .topWeight, formula: .epley), 100)
    }

    func testEmptyHistoryHasNoBest() {
        XCTAssertNil(PRCalculator.best([], rule: .topWeight, formula: .epley))
        XCTAssertNil(PRCalculator.best([s(0, 0)], rule: .topWeight, formula: .epley))
    }

    func testNewPRWithNoHistoryIsPR() {
        XCTAssertTrue(PRCalculator.isNewPR(candidate: s(100, 5), previous: [], rule: .topWeight, formula: .epley))
    }

    func testNewPRStrictlyExceeds() {
        let prev = [s(100, 5)]
        XCTAssertTrue(PRCalculator.isNewPR(candidate: s(101, 5), previous: prev, rule: .topWeight, formula: .epley))
        // tie is NOT a PR
        XCTAssertFalse(PRCalculator.isNewPR(candidate: s(100, 5), previous: prev, rule: .topWeight, formula: .epley))
        XCTAssertFalse(PRCalculator.isNewPR(candidate: s(99, 5), previous: prev, rule: .topWeight, formula: .epley))
    }

    func testWarmupCandidateNeverPR() {
        XCTAssertFalse(PRCalculator.isNewPR(candidate: s(500, 1, warmup: true), previous: [], rule: .topWeight, formula: .epley))
    }

    func testBestSampleReturnsAchievingSet() {
        let samples = [s(100, 5), s(110, 1)]
        let best = PRCalculator.bestSample(samples, rule: .topWeight, formula: .epley)
        XCTAssertEqual(best?.weight, 110)
    }
}
