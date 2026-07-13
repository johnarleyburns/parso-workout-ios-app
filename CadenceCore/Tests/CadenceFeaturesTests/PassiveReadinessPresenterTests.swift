import XCTest
import CadenceCore
@testable import CadenceFeatures

/// The passive-readiness Home line is prepared here, headlessly. The HARD RULE is
/// mechanically enforced: a shown claim always carries a resolvable citation.
final class PassiveReadinessPresenterTests: XCTestCase {

    private func snapshot(passive: PassiveReadinessSignal?, promptCheckIn: Bool = false) -> ReadinessSnapshot {
        ReadinessSnapshot(soreness: nil, sleepQuality: nil, stress: nil, motivation: nil,
                          painConcern: false, capturedAt: nil, confidence: .low,
                          passive: passive, promptCheckIn: promptCheckIn)
    }

    func testNilReadinessProducesNoLine() {
        XCTAssertNil(PassiveReadinessPresenter.display(for: nil))
    }

    func testInsufficientPassiveProducesNoLine() {
        let s = snapshot(passive: .insufficient)
        XCTAssertNil(PassiveReadinessPresenter.display(for: s))
    }

    func testNormalPassiveProducesNoLine() {
        let s = snapshot(passive: PassiveReadinessSignal(level: .normal))
        XCTAssertNil(PassiveReadinessPresenter.display(for: s),
                     "normal makes no claim → no card")
    }

    func testSuppressedProducesLineWithCitations() {
        let signal = PassiveReadinessSignal(level: .suppressed,
                                            hrvDeviationPct: -14,
                                            citationIds: PassiveReadinessAnalyzer.claimCitationIds)
        guard let display = PassiveReadinessPresenter.display(for: snapshot(passive: signal)) else {
            return XCTFail("expected a display for a suppressed signal")
        }
        XCTAssertFalse(display.message.isEmpty)
        XCTAssertFalse(display.citationIds.isEmpty, "HARD RULE: a claim must carry citations")
        XCTAssertTrue(display.message.contains("14"), "HRV deviation should appear in the copy")
    }

    /// HARD RULE, mechanically enforced: every citation id the presenter surfaces
    /// must resolve to a real, navigable Citation.
    func testEveryShownCitationResolves() {
        let signal = PassiveReadinessSignal(level: .stronglySuppressed,
                                            hrvDeviationPct: -22,
                                            restingHRDeltaBpm: 6,
                                            sleepDebtHours: 2.5,
                                            citationIds: PassiveReadinessAnalyzer.claimCitationIds)
        let display = PassiveReadinessPresenter.display(for: snapshot(passive: signal))
        XCTAssertNotNil(display)
        for id in display!.citationIds {
            XCTAssertNotNil(CitationRegistry.citation(forId: id),
                            "presenter surfaced unresolved citation id: \(id)")
        }
    }

    /// A claim whose citationIds were (defensively) empty must never render a line —
    /// we never show an uncited coaching claim.
    func testClaimWithoutCitationsIsSuppressed() {
        let signal = PassiveReadinessSignal(level: .suppressed, hrvDeviationPct: -14, citationIds: [])
        XCTAssertNil(PassiveReadinessPresenter.display(for: snapshot(passive: signal)))
    }

    func testPromptCheckInFlows() {
        let signal = PassiveReadinessSignal(level: .stronglySuppressed,
                                            hrvDeviationPct: -25,
                                            citationIds: PassiveReadinessAnalyzer.claimCitationIds)
        let display = PassiveReadinessPresenter.display(for: snapshot(passive: signal, promptCheckIn: true))
        XCTAssertEqual(display?.promptCheckIn, true)
    }
}
