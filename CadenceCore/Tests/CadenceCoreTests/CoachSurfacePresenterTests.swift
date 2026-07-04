import XCTest
@testable import CadenceCore

final class CoachSurfacePresenterTests: XCTestCase {

    private func state(_ entitlement: ProEntitlement = .free,
                       hidden: Bool = false,
                       introImpressions: Int = CoachSurfacePresenter.introImpressionCap,
                       hasInsight: Bool = false,
                       protocolPackPending: Bool = false) -> CoachSurfaceState {
        CoachSurfacePresenter.state(
            entitlement: entitlement,
            hidden: hidden,
            introImpressions: introImpressions,
            hasInsight: hasInsight,
            protocolPackPending: protocolPackPending)
    }

    func testProEntitlementShowsCoachingCard() {
        XCTAssertEqual(state(.pro(source: .lifetime)), .pro)
        XCTAssertEqual(state(.pro(source: .subscription)), .pro)
        XCTAssertTrue(state(.pro(source: .lifetime)).showsCoachingCard)
    }

    func testTrialEntitlementIsTrialState() {
        XCTAssertEqual(state(.pro(source: .trial)), .trial)
        XCTAssertTrue(state(.pro(source: .trial)).showsCoachingCard)
    }

    func testEntitlementOverridesHiddenAndImpressions() {
        // Even if the user hid offers while free, becoming Pro shows the card.
        XCTAssertEqual(state(.pro(source: .subscription), hidden: true, introImpressions: 0), .pro)
    }

    func testNewUserStartsIntroducing() {
        XCTAssertEqual(state(introImpressions: 0), .introducing)
        XCTAssertEqual(state(introImpressions: 2), .introducing)
    }

    func testDemotesToAmbientAfterImpressionCap() {
        XCTAssertEqual(state(introImpressions: CoachSurfacePresenter.introImpressionCap, hasInsight: false),
                       .ambient)
    }

    func testInsightStateWhenObservationAvailable() {
        XCTAssertEqual(state(introImpressions: 3, hasInsight: true), .insight)
        XCTAssertTrue(state(introImpressions: 3, hasInsight: true).showsCompactRow)
    }

    func testHiddenState() {
        XCTAssertEqual(state(hidden: true), .hidden)
        XCTAssertFalse(state(hidden: true).showsCompactRow)
        XCTAssertFalse(state(hidden: true).showsCoachingCard)
    }

    func testProtocolPackReTriggersIntroducingEvenAfterCap() {
        XCTAssertEqual(state(introImpressions: 99, hasInsight: true, protocolPackPending: true),
                       .introducing)
    }

    func testHiddenBeatsProtocolPackForFreeUser() {
        // A hidden free user is not re-pitched by a protocol pack on Home.
        XCTAssertEqual(state(hidden: true, protocolPackPending: true), .hidden)
    }

    func testAmbientVsInsightOnlyDiffersByObservation() {
        XCTAssertEqual(state(introImpressions: 5, hasInsight: false), .ambient)
        XCTAssertEqual(state(introImpressions: 5, hasInsight: true), .insight)
    }
}
