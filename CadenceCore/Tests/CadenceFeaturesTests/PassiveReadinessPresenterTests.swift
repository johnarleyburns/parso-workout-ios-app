import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

/// The passive-readiness Home line is prepared here, headlessly. The HARD RULE is
/// mechanically enforced: a shown claim always carries a resolvable citation.
struct PassiveReadinessPresenterTests {

    private func snapshot(passive: PassiveReadinessSignal?, promptCheckIn: Bool = false) -> ReadinessSnapshot {
        ReadinessSnapshot(soreness: nil, sleepQuality: nil, stress: nil, motivation: nil,
                          painConcern: false, capturedAt: nil, confidence: .low,
                          passive: passive, promptCheckIn: promptCheckIn)
    }

    @Test func nilReadinessProducesNoLine() {
        #expect(PassiveReadinessPresenter.display(for: nil) == nil)
    }

    @Test func insufficientPassiveProducesNoLine() {
        let s = snapshot(passive: .insufficient)
        #expect(PassiveReadinessPresenter.display(for: s) == nil)
    }

    @Test func normalPassiveProducesNoLine() {
        let s = snapshot(passive: PassiveReadinessSignal(level: .normal))
        #expect(PassiveReadinessPresenter.display(for: s) == nil,
                "normal makes no claim → no card")
    }

    @Test func suppressedProducesLineWithCitations() {
        let signal = PassiveReadinessSignal(level: .suppressed,
                                            hrvDeviationPct: -14,
                                            citationIds: PassiveReadinessAnalyzer.claimCitationIds)
        guard let display = PassiveReadinessPresenter.display(for: snapshot(passive: signal)) else {
            Issue.record("expected a display for a suppressed signal")
            return
        }
        #expect(!display.message.isEmpty)
        #expect(!display.citationIds.isEmpty, "HARD RULE: a claim must carry citations")
        #expect(display.message.contains("14"), "HRV deviation should appear in the copy")
    }

    /// HARD RULE, mechanically enforced: every citation id the presenter surfaces
    /// must resolve to a real, navigable Citation.
    @Test func everyShownCitationResolves() {
        let signal = PassiveReadinessSignal(level: .stronglySuppressed,
                                            hrvDeviationPct: -22,
                                            restingHRDeltaBpm: 6,
                                            sleepDebtHours: 2.5,
                                            citationIds: PassiveReadinessAnalyzer.claimCitationIds)
        let display = PassiveReadinessPresenter.display(for: snapshot(passive: signal))
        #expect(display != nil)
        for id in display!.citationIds {
            #expect(CitationRegistry.citation(forId: id) != nil,
                    "presenter surfaced unresolved citation id: \(id)")
        }
    }

    /// A claim whose citationIds were (defensively) empty must never render a line —
    /// we never show an uncited coaching claim.
    @Test func claimWithoutCitationsIsSuppressed() {
        let signal = PassiveReadinessSignal(level: .suppressed, hrvDeviationPct: -14, citationIds: [])
        #expect(PassiveReadinessPresenter.display(for: snapshot(passive: signal)) == nil)
    }

    @Test func promptCheckInFlows() {
        let signal = PassiveReadinessSignal(level: .stronglySuppressed,
                                            hrvDeviationPct: -25,
                                            citationIds: PassiveReadinessAnalyzer.claimCitationIds)
        let display = PassiveReadinessPresenter.display(for: snapshot(passive: signal, promptCheckIn: true))
        #expect(display?.promptCheckIn == true)
    }
}
