import XCTest
import CadenceCore
@testable import CadenceFeatures

final class TodayRecommendationRowsPresenterTests: XCTestCase {
    private let strength = CoachSession(
        id: "s1", kind: .strength, title: "Upper", durationMinutes: 45,
        exercises: [.init(name: "Bench Press", sets: 3, repsLow: 8)],
        citationIds: [], launchPayload: .strengthPlan("Upper"))
    private let cardio = CoachSession(
        id: "c1", kind: .easyAerobic, title: "Easy walk", durationMinutes: 30,
        launchPayload: .cardio(type: "walk", durationMinutes: 30))

    private func slots(strengthCompanion: Bool) -> [DailyRecommendationSlot] {
        // Deliberately cardio-first to prove deterministic ordering.
        [DailyRecommendationSlot(modality: .cardio, session: cardio, isCompanion: !strengthCompanion ? true : false),
         DailyRecommendationSlot(modality: .strength, session: strength, isCompanion: strengthCompanion)]
    }

    func testOrderAndBadgesWhenTwoADaysOff() {
        let rows = TodayRecommendationRowsPresenter.rows(slots: slots(strengthCompanion: false), allowsTwoADays: false)
        XCTAssertEqual(rows.map(\.modality), [.strength, .cardio])
        XCTAssertEqual(rows.map(\.badge), [.recommended, .optionalToday])
        XCTAssertEqual(rows[0].startIdentifier, "home.todayRecommendation.strength.start")
        XCTAssertEqual(rows[1].startIdentifier, "home.todayRecommendation.cardio.start")
        XCTAssertEqual(rows[1].durationText, "30 min")
    }

    func testCompanionBadgeWhenTwoADaysOn() {
        let rows = TodayRecommendationRowsPresenter.rows(slots: slots(strengthCompanion: false), allowsTwoADays: true)
        XCTAssertEqual(rows.map(\.badge), [.recommended, .alsoPlannedToday])
        XCTAssertEqual(TodayRecommendationBadge.alsoPlannedToday.label, "Also planned today")
        XCTAssertEqual(TodayRecommendationBadge.optionalToday.label, "Optional today")
    }

    func testCardioPrimaryMakesStrengthTheCompanion() {
        let s = [DailyRecommendationSlot(modality: .strength, session: strength, isCompanion: true),
                 DailyRecommendationSlot(modality: .cardio, session: cardio, isCompanion: false)]
        let rows = TodayRecommendationRowsPresenter.rows(slots: s, allowsTwoADays: false)
        XCTAssertEqual(rows.map(\.badge), [.optionalToday, .recommended])
    }

    func testSingleSlotRendersOneRowAndNoSlotsNone() {
        let one = [DailyRecommendationSlot(modality: .cardio, session: cardio, isCompanion: false)]
        XCTAssertEqual(TodayRecommendationRowsPresenter.rows(slots: one, allowsTwoADays: false).map(\.modality), [.cardio])
        XCTAssertTrue(TodayRecommendationRowsPresenter.rows(slots: [], allowsTwoADays: true).isEmpty)
    }

    func testRowsCarryTheOriginalSessionForRouting() {
        let rows = TodayRecommendationRowsPresenter.rows(slots: slots(strengthCompanion: false), allowsTwoADays: false)
        XCTAssertEqual(rows.map(\.session.id), ["s1", "c1"])
        if case .planEditor = CoachRouter.destination(for: rows[0].session) {} else { XCTFail("strength routes to editor") }
        XCTAssertEqual(CoachRouter.destination(for: rows[1].session), .outdoorCardio(.walk))
    }

    func testStrengthRowRejectsACardioSessionEvenWhenSlotIsLabelledStrength() {
        let malformed = [
            DailyRecommendationSlot(modality: .strength, session: cardio, isCompanion: false),
            DailyRecommendationSlot(modality: .cardio, session: cardio, isCompanion: true)
        ]

        let rows = TodayRecommendationRowsPresenter.rows(slots: malformed, allowsTwoADays: false)

        XCTAssertEqual(rows.map(\.modality), [.cardio])
        XCTAssertEqual(rows.first?.session.id, cardio.id)
        XCTAssertFalse(rows.contains { $0.modality == .strength && $0.session.isAerobic })
    }
}
