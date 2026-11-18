import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

/// Field-test batch 2026-08-20 issue 7: the zone-color mapping the cardio live
/// screens use must match the Apple Watch's scheme, and the `LiveHRBigView`
/// subtitle/bpm copy is asserted headlessly rather than in the simulator (the
/// smoke flow has no live HR source).
struct HRZoneTintTests {

    // MARK: - HRZoneTint

    @Test func tintMappingMatchesWatchScheme() {
        #expect(HRZoneTint.tint(for: 1) == .zone1) // Z1 cyan
        #expect(HRZoneTint.tint(for: 2) == .zone2) // Z2 green
        #expect(HRZoneTint.tint(for: 3) == .zone3) // Z3 yellow
        #expect(HRZoneTint.tint(for: 4) == .zone4) // Z4 orange
        #expect(HRZoneTint.tint(for: 5) == .zone5) // Z5 red
    }

    @Test func tintOutOfRangeIsNeutral() {
        #expect(HRZoneTint.tint(for: 0) == .neutral)
        #expect(HRZoneTint.tint(for: 6) == .neutral)
        #expect(HRZoneTint.tint(for: -1) == .neutral)
    }

    // MARK: - LiveHRPresenter.connectionNote

    @Test func connectionNoteShownWhenWatchSampleStale() {
        #expect(LiveHRPresenter.connectionNote(isAppleWatchSource: true, isSampleFresh: false, statusText: "Reconnecting") == "Reconnecting")
    }

    @Test func connectionNoteNilWhenFreshOrNotWatch() {
        #expect(LiveHRPresenter.connectionNote(isAppleWatchSource: true, isSampleFresh: true, statusText: "Receiving live HR") == nil)
        #expect(LiveHRPresenter.connectionNote(isAppleWatchSource: false, isSampleFresh: false, statusText: "x") == nil)
    }

    // MARK: - LiveHRPresenter

    @Test func subtitleZones() {
        #expect(LiveHRPresenter.subtitle(zone: 3, avgHR: nil) == "Z3 · Aerobic")
        #expect(LiveHRPresenter.subtitle(zone: 5, avgHR: nil) == "Z5 · Max")
        #expect(LiveHRPresenter.subtitle(zone: 1, avgHR: nil) == "Z1 · Recovery")
        #expect(LiveHRPresenter.subtitle(zone: 2, avgHR: nil) == "Z2 · Easy")
        #expect(LiveHRPresenter.subtitle(zone: 4, avgHR: nil) == "Z4 · Threshold")
    }

    @Test func subtitleAverageSuffix() {
        #expect(LiveHRPresenter.subtitle(zone: 3, avgHR: 138.4) == "Z3 · Aerobic · Avg 138 bpm")
        #expect(LiveHRPresenter.subtitle(zone: 5, avgHR: 190.6) == "Z5 · Max · Avg 191 bpm")
    }

    @Test func subtitleNilAverageOmitsSuffix() {
        #expect(LiveHRPresenter.subtitle(zone: 3, avgHR: nil) == "Z3 · Aerobic")
        #expect(LiveHRPresenter.subtitle(zone: 3, avgHR: 0) == "Z3 · Aerobic · Avg 0 bpm")
    }

    @Test func zoneLineAndAvgSuffixComposeTheSubtitle() {
        let zone = 4
        let avg: Double? = 160.2
        #expect(LiveHRPresenter.zoneLine(zone: zone) + LiveHRPresenter.avgSuffix(avgHR: avg) ==
                       LiveHRPresenter.subtitle(zone: zone, avgHR: avg))
        #expect(LiveHRPresenter.avgSuffix(avgHR: nil) == "")
    }

    @Test func bpmText() {
        #expect(LiveHRPresenter.bpmText(143.2) == "143")
        #expect(LiveHRPresenter.bpmText(nil) == "—")
        #expect(LiveHRPresenter.bpmText(0) == "0")
    }
}

struct HRZoneBandsTests {
    @Test func bandsFollowUserMaxAndClipToDomain() {
        let domain = HRZoneBands.domain(bpms: [100, 150], maxHR: 200)
        #expect(domain == 100...200)
        let bands = HRZoneBands.bands(maxHR: 200, domain: domain)
        #expect(bands.map(\.zone) == [1, 2, 3, 4, 5])
        #expect(bands[0].lower == 100); #expect(bands[0].upper == 120)
        #expect(bands[3].lower == 160); #expect(bands[3].upper == 180)
        #expect(bands[4].upper == 200)
        #expect(bands[4].tint == .zone5)
    }

    @Test func bandsOmitZonesOutsideDomain() {
        let bands = HRZoneBands.bands(maxHR: 200, domain: 130...175)
        #expect(bands.map(\.zone) == [2, 3, 4])
        #expect(HRZoneBands.bands(maxHR: 0, domain: 0...10).isEmpty)
    }
}
