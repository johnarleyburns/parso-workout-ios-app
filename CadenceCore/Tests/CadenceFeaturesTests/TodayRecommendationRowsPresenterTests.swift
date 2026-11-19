import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct TodayRecommendationRowsPresenterTests {
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

    @Test func orderAndBadgesWhenTwoADaysOff() {
        let rows = TodayRecommendationRowsPresenter.rows(slots: slots(strengthCompanion: false), allowsTwoADays: false)
        #expect(rows.map(\.modality) == [.strength, .cardio])
        #expect(rows.map(\.badge) == [.recommended, .optionalToday])
        #expect(rows[0].startIdentifier == "home.todayRecommendation.strength.start")
        #expect(rows[1].startIdentifier == "home.todayRecommendation.cardio.start")
        #expect(rows[1].durationText == "30 min")
    }

    @Test func companionBadgeWhenTwoADaysOn() {
        let rows = TodayRecommendationRowsPresenter.rows(slots: slots(strengthCompanion: false), allowsTwoADays: true)
        #expect(rows.map(\.badge) == [.recommended, .alsoPlannedToday])
        #expect(TodayRecommendationBadge.alsoPlannedToday.label == "Also planned today")
        #expect(TodayRecommendationBadge.optionalToday.label == "Optional today")
    }

    @Test func cardioPrimaryMakesStrengthTheCompanion() {
        let s = [DailyRecommendationSlot(modality: .strength, session: strength, isCompanion: true),
                 DailyRecommendationSlot(modality: .cardio, session: cardio, isCompanion: false)]
        let rows = TodayRecommendationRowsPresenter.rows(slots: s, allowsTwoADays: false)
        #expect(rows.map(\.badge) == [.optionalToday, .recommended])
    }

    @Test func singleSlotRendersOneRowAndNoSlotsNone() {
        let one = [DailyRecommendationSlot(modality: .cardio, session: cardio, isCompanion: false)]
        #expect(TodayRecommendationRowsPresenter.rows(slots: one, allowsTwoADays: false).map(\.modality) == [.cardio])
        #expect(TodayRecommendationRowsPresenter.rows(slots: [], allowsTwoADays: true).isEmpty)
    }

    @Test func rowsCarryTheOriginalSessionForRouting() {
        let rows = TodayRecommendationRowsPresenter.rows(slots: slots(strengthCompanion: false), allowsTwoADays: false)
        #expect(rows.map(\.session.id) == ["s1", "c1"])
        if case .planEditor = CoachRouter.destination(for: rows[0].session) {} else { Issue.record("strength routes to editor") }
        #expect(CoachRouter.destination(for: rows[1].session) == .outdoorCardio(.walk))
    }

    @Test func strengthRowRejectsACardioSessionEvenWhenSlotIsLabelledStrength() {
        let malformed = [
            DailyRecommendationSlot(modality: .strength, session: cardio, isCompanion: false),
            DailyRecommendationSlot(modality: .cardio, session: cardio, isCompanion: true)
        ]

        let rows = TodayRecommendationRowsPresenter.rows(slots: malformed, allowsTwoADays: false)

        #expect(rows.map(\.modality) == [.cardio])
        #expect(rows.first?.session.id == cardio.id)
        #expect(!rows.contains { $0.modality == .strength && $0.session.isAerobic })
    }
}
