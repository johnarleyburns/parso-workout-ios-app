import Foundation
import Testing
@testable import CadenceCore

struct PRCalculatorTests {

    private func s(_ w: Double, _ r: Int, warmup: Bool = false, day: Int = 0) -> SetSample {
        SetSample(weight: w, reps: r, date: Date(timeIntervalSince1970: TimeInterval(day) * 86_400), isWarmup: warmup)
    }

    @Test func bestTopWeight() {
        let samples = [s(100, 5), s(110, 1), s(105, 3)]
        #expect(PRCalculator.best(samples, rule: .topWeight, formula: .epley) == 110)
    }

    @Test func bestEstimated1RM() {
        // 100x5 → 116.67 ; 110x1 → 110 ; so 100x5 wins on e1RM
        let samples = [s(100, 5), s(110, 1)]
        #expect(abs(PRCalculator.best(samples, rule: .estimated1RM, formula: .epley)! - 116.67) <= 0.01)
    }

    @Test func bestTopVolume() {
        let samples = [s(100, 5), s(80, 10)] // 500 vs 800
        #expect(PRCalculator.best(samples, rule: .topVolume, formula: .epley) == 800)
    }

    @Test func warmupsIgnored() {
        let samples = [s(200, 1, warmup: true), s(100, 5)]
        #expect(PRCalculator.best(samples, rule: .topWeight, formula: .epley) == 100)
    }

    @Test func emptyHistoryHasNoBest() {
        #expect(PRCalculator.best([], rule: .topWeight, formula: .epley) == nil)
        #expect(PRCalculator.best([s(0, 0)], rule: .topWeight, formula: .epley) == nil)
    }

    @Test func newPRWithNoHistoryIsPR() {
        #expect(PRCalculator.isNewPR(candidate: s(100, 5), previous: [], rule: .topWeight, formula: .epley))
    }

    @Test func newPRStrictlyExceeds() {
        let prev = [s(100, 5)]
        #expect(PRCalculator.isNewPR(candidate: s(101, 5), previous: prev, rule: .topWeight, formula: .epley))
        // tie is NOT a PR
        #expect(!PRCalculator.isNewPR(candidate: s(100, 5), previous: prev, rule: .topWeight, formula: .epley))
        #expect(!PRCalculator.isNewPR(candidate: s(99, 5), previous: prev, rule: .topWeight, formula: .epley))
    }

    @Test func warmupCandidateNeverPR() {
        #expect(!PRCalculator.isNewPR(candidate: s(500, 1, warmup: true), previous: [], rule: .topWeight, formula: .epley))
    }

    @Test func bestSampleReturnsAchievingSet() {
        let samples = [s(100, 5), s(110, 1)]
        let best = PRCalculator.bestSample(samples, rule: .topWeight, formula: .epley)
        #expect(best?.weight == 110)
    }
}
