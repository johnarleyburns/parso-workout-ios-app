import XCTest
@testable import CadenceCore

/// D4 in code: self-report is authoritative where fresh; passive signals fill the
/// gap at lower confidence and, when strongly suppressed with no check-in, prompt
/// one. The named invariant `test_selfReportBeatsContradictingPassiveSignal` is the
/// one that guarantees the coach never contradicts `sawMonitoring2016`.
final class ReadinessFusionTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func selfReport(good: Bool, ageHours: Double) -> ReadinessSnapshot {
        ReadinessSnapshot(
            soreness: good ? 5 : 2,
            sleepQuality: good ? 5 : 2,
            stress: good ? 5 : 2,
            motivation: good ? 5 : 2,
            painConcern: false,
            capturedAt: now.addingTimeInterval(-ageHours * 3600),
            confidence: .moderate)
    }

    private func passive(_ level: PassiveReadinessLevel) -> PassiveReadinessSignal {
        level == .insufficientData
            ? .insufficient
            : PassiveReadinessSignal(level: level,
                                     hrvDeviationPct: level == .stronglySuppressed ? -25 : -12,
                                     citationIds: PassiveReadinessAnalyzer.claimCitationIds)
    }

    // MARK: The D4 invariant

    func test_selfReportBeatsContradictingPassiveSignal() {
        // Fresh self-report says "I feel great"; passive HRV says "strongly
        // suppressed". Self-report MUST win (sawMonitoring2016).
        let fused = ReadinessFusion.fuse(
            selfReport: selfReport(good: true, ageHours: 2),
            passive: passive(.stronglySuppressed),
            now: now)
        XCTAssertFalse(fused.isPoor, "a fresh good self-report must not be overridden by HRV")
        XCTAssertFalse(fused.promptCheckIn, "we already have a fresh check-in")
        XCTAssertEqual(fused.passive?.level, .stronglySuppressed, "passive is retained as context")
    }

    func testFreshPoorSelfReportIsRespectedToo() {
        let fused = ReadinessFusion.fuse(
            selfReport: selfReport(good: false, ageHours: 2),
            passive: passive(.normal),
            now: now)
        XCTAssertTrue(fused.isPoor, "a fresh poor self-report stands even when passive is normal")
    }

    // MARK: staleness

    func testStaleSelfReportDoesNotWin() {
        // A 30h-old "great" check-in must NOT override a strongly-suppressed passive
        // signal — it is no longer fresh.
        let fused = ReadinessFusion.fuse(
            selfReport: selfReport(good: true, ageHours: 30),
            passive: passive(.stronglySuppressed),
            now: now)
        XCTAssertTrue(fused.promptCheckIn,
                      "stale self-report + strong passive suppression should prompt a check-in")
        XCTAssertEqual(fused.confidence, .low)
    }

    // MARK: passive-only path

    func testPassiveOnlyYieldsReducedConfidence() {
        let fused = ReadinessFusion.fuse(selfReport: nil, passive: passive(.suppressed), now: now)
        XCTAssertEqual(fused.confidence, .low, "no check-in → passive drives a low-confidence estimate")
        XCTAssertTrue(fused.isPoor)
        XCTAssertNil(fused.capturedAt, "passive-only readiness has no self-report timestamp")
    }

    func testCorroboratingPassiveRaisesConfidence() {
        // Fresh poor self-report + suppressed passive agree → confidence bumps up.
        let fused = ReadinessFusion.fuse(
            selfReport: selfReport(good: false, ageHours: 2),
            passive: passive(.suppressed),
            now: now)
        XCTAssertEqual(fused.confidence, .high, "objective agreement should raise confidence")
    }

    // MARK: promptCheckIn

    func testPromptCheckInOnlyOnStronglySuppressedWithNoCheckIn() {
        XCTAssertTrue(ReadinessFusion.fuse(selfReport: nil,
                                           passive: passive(.stronglySuppressed),
                                           now: now).promptCheckIn)
        // Suppressed (not strong) does not prompt.
        XCTAssertFalse(ReadinessFusion.fuse(selfReport: nil,
                                            passive: passive(.suppressed),
                                            now: now).promptCheckIn)
        // Strong but a fresh check-in exists → no prompt.
        XCTAssertFalse(ReadinessFusion.fuse(selfReport: selfReport(good: true, ageHours: 1),
                                            passive: passive(.stronglySuppressed),
                                            now: now).promptCheckIn)
    }

    func testInsufficientPassiveAndNoSelfReportIsQuiet() {
        let fused = ReadinessFusion.fuse(selfReport: nil, passive: .insufficient, now: now)
        XCTAssertFalse(fused.promptCheckIn)
        XCTAssertFalse(fused.isPoor)
        XCTAssertEqual(fused.confidence, .low)
    }
}
