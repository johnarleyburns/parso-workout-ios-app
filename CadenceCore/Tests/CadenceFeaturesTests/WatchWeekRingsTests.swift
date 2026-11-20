import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchWeekRingsTests {
    @Test func toneBands() {
        func tone(_ v: Double) -> WatchWeekRingTone {
            WatchWeekRing(kind: .strength, value: v, minimum: 20, target: 60).tone
        }
        #expect(tone(0) == .red)
        #expect(tone(1) == .yellow)
        #expect(tone(19.9) == .yellow)
        #expect(tone(127) == .yellow)
        #expect(tone(128) == .lightGreen)
        #expect(tone(191) == .lightGreen)
        #expect(tone(192) == .green)
    }

    @Test func progressClampsAndHandlesZeroTarget() {
        #expect(WatchWeekRing(kind: .cardio, value: 450, minimum: 150, target: 300).progress == 1)
        #expect(WatchWeekRing(kind: .cardio, value: 150, minimum: 150, target: 300).progress == 0.5)
        #expect(WatchWeekRing(kind: .cardio, value: 10, minimum: 0, target: 0).progress == 0)
    }

    @Test func ringsOrderAndDefaults() {
        let empty = WatchWeekRings.rings(from: nil)
        #expect(empty.map(\.kind) == [.strength, .cardio])
        #expect(empty.map(\.tone) == [.red, .red])
        #expect(empty[1].minimum == 150)
        #expect(empty[1].target == 300)

        let summary = WatchSync.WeekSummary(sets: 30, setsMinimum: 40, setsTarget: 120,
                                            cardioMinutes: 200, updatedAt: Date())
        let rings = WatchWeekRings.rings(from: summary)
        #expect(rings[0].tone == .yellow)
        #expect(rings[1].tone == .lightGreen)
        #expect(rings[1].displayValue == 200)
    }

    @Test func overlayAddsToBaselineForCurrentWeekOnly() {
        let baseline = WatchSync.WeekSummary(sets: 111, setsMinimum: 40, setsTarget: 120,
                                             cardioMinutes: 76, updatedAt: Date())
        let overlays = [
            WatchWeekLocalOverlay(id: UUID(), weekKey: "2026-11-02", kind: .strength,
                                  sets: 5, completedAt: Date()),
            WatchWeekLocalOverlay(id: UUID(), weekKey: "2026-11-02", kind: .cardio,
                                  moderateEquivalentMinutes: 30, completedAt: Date()),
            // A previous week's unresolved overlay must never leak into the current week.
            WatchWeekLocalOverlay(id: UUID(), weekKey: "2026-10-26", kind: .strength,
                                  sets: 99, completedAt: Date()),
        ]
        let rings = WatchWeekRings.rings(baseline: baseline, overlays: overlays, currentWeekKey: "2026-11-02")
        #expect(rings[0].value == 116)
        #expect(rings[1].value == 106)
    }

    @Test func acknowledgedOverlayIsNotDoubleCountedAgainstTheNewBaseline() {
        let staleBaseline = WatchSync.WeekSummary(sets: 111, setsMinimum: 40, setsTarget: 120,
                                                  cardioMinutes: 76, updatedAt: Date())
        let overlays = [
            WatchWeekLocalOverlay(id: UUID(), weekKey: "2026-11-02", kind: .strength,
                                  sets: 5, completedAt: Date()),
            WatchWeekLocalOverlay(id: UUID(), weekKey: "2026-11-02", kind: .cardio,
                                  moderateEquivalentMinutes: 30, completedAt: Date()),
        ]
        let beforeReconnect = WatchWeekRings.rings(baseline: staleBaseline, overlays: overlays, currentWeekKey: "2026-11-02")
        #expect(beforeReconnect[0].value == 116)
        #expect(beforeReconnect[1].value == 106)

        // The phone's new baseline already includes the acknowledged completions;
        // once acknowledged, the overlay list is empty, so the total must land on
        // the new baseline exactly — never baseline + overlay (121/136).
        let freshBaseline = WatchSync.WeekSummary(sets: 116, setsMinimum: 40, setsTarget: 120,
                                                  cardioMinutes: 106, updatedAt: Date())
        let afterReconnect = WatchWeekRings.rings(baseline: freshBaseline, overlays: [], currentWeekKey: "2026-11-02")
        #expect(afterReconnect[0].value == 116)
        #expect(afterReconnect[1].value == 106)
    }

    @Test func weekSummaryContextRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_000)
        let summary = WatchSync.WeekSummary(sets: 12.5, setsMinimum: 40, setsTarget: 120,
                                            cardioMinutes: 95, updatedAt: date)
        let context = WatchSync.WeekSummary.contextDict(summary)
        #expect(WatchSync.WeekSummary.from(context: context) == summary)
        #expect(WatchSync.WeekSummary.from(context: [:]) == nil)
        let incoming = WatchSync.IncomingContext.from(
            context: context, applyingTo: WatchSync.Preferences())
        #expect(incoming.weekSummary == summary)
    }

    @Test func measuredStrengthOverlayAddsSetsAndModerateEquivalentMinutes() {
        let id = UUID(), date = Date(timeIntervalSince1970: 1_800_000_000)
        let baseline = WatchSync.WeekSummary(sets: 10, setsMinimum: 40, setsTarget: 120,
                                             cardioMinutes: 20, updatedAt: date)
        let overlay = WatchWeekLocalOverlay(id: id, weekKey: "2026-11-09", kind: .strength,
                                            sets: 4, moderateEquivalentMinutes: 12.5, completedAt: date)
        let rings = WatchWeekRings.rings(baseline: baseline, overlays: [overlay], currentWeekKey: "2026-11-09")
        #expect(abs((rings.first { $0.kind == .strength }?.value ?? -1) - 14) <= 0.001)
        #expect(abs((rings.first { $0.kind == .cardio }?.value ?? -1) - 32.5) <= 0.001)
    }

    @Test func sameStrengthCompletionIDReplacesInsteadOfDoubleCounting() {
        let id = UUID(), date = Date(timeIntervalSince1970: 1_800_000_000)
        let defaults = InMemoryDefaultsStore()
        let store = WatchWeekLocalOverlayStore(defaults: defaults)
        for _ in 0..<2 {
            store.record(WatchWeekLocalOverlay(id: id, weekKey: "w", kind: .strength, sets: 4,
                                               moderateEquivalentMinutes: 12.5, completedAt: date))
        }
        let rings = WatchWeekRings.rings(baseline: nil, overlays: store.overlays(forWeekKey: "w"), currentWeekKey: "w")
        #expect(abs((rings.first { $0.kind == .strength }?.value ?? -1) - 4) <= 0.001)
        #expect(abs((rings.first { $0.kind == .cardio }?.value ?? -1) - 12.5) <= 0.001)
    }
}
