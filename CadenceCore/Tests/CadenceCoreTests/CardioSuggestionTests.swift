import XCTest
@testable import CadenceCore

final class CardioSuggestionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testEmptyHistoryProducesModerateStarter() {
        let result = CardioSuggestionGenerator.generate(
            input: CardioSuggestionInput(weeklyModerateEquivalentMinutes: 0,
                                         experience: .beginner, asOf: now))

        XCTAssertEqual(result?.type, .run)
        XCTAssertEqual(result?.intensity, .moderate)
        XCTAssertEqual(result?.durationMinutes, 45)
        XCTAssertTrue(result?.indoor == true)
        XCTAssertFalse(result?.isInterval == true)
    }

    func testRecentTypeAndWeeklyGapBoundDuration() {
        let history = [CardioSuggestionHistory(
            type: .rowing, durationMinutes: 32, moderateEquivalentMinutes: 32,
            intensity: .moderate, start: now.addingTimeInterval(-86_400))]
        let result = CardioSuggestionGenerator.generate(
            input: CardioSuggestionInput(history: history,
                                         weeklyModerateEquivalentMinutes: 135,
                                         asOf: now))

        XCTAssertEqual(result?.type, .rowing)
        XCTAssertEqual(result?.durationMinutes, 20)
        XCTAssertEqual(result?.intensity, .moderate)
    }

    func testBeginnerNeverReceivesIntervals() {
        let history = (0..<4).map { index in
            CardioSuggestionHistory(
                type: .hiit, durationMinutes: 25, moderateEquivalentMinutes: 50,
                intensity: .veryHard, isInterval: true,
                start: now.addingTimeInterval(TimeInterval(-index * 86_400)))
        }
        let result = CardioSuggestionGenerator.generate(
            input: CardioSuggestionInput(history: history,
                                         weeklyModerateEquivalentMinutes: 0,
                                         experience: .beginner, asOf: now))

        XCTAssertEqual(result?.intensity, .moderate)
        XCTAssertFalse(result?.isInterval == true)
    }

    func testEstablishedRecentIntervalsCanProduceBoundedIntervals() {
        let history = (0..<4).map { index in
            CardioSuggestionHistory(
                type: .hiit, durationMinutes: 25, moderateEquivalentMinutes: 50,
                intensity: .veryHard, isInterval: true,
                start: now.addingTimeInterval(TimeInterval(-index * 86_400)))
        }
        let result = CardioSuggestionGenerator.generate(
            input: CardioSuggestionInput(history: history,
                                         weeklyModerateEquivalentMinutes: 0,
                                         experience: .intermediate, asOf: now))

        XCTAssertEqual(result?.type, .hiit)
        XCTAssertEqual(result?.intensity, .interval)
        XCTAssertEqual(result?.intervalRounds, 4)
        XCTAssertEqual(result?.intervalWorkSeconds, 120)
        XCTAssertEqual(result?.intervalRestSeconds, 120)
        XCTAssertEqual(result?.durationMinutes, 25)
    }

    func testValueRoundTripAndCitationContract() throws {
        let input = CardioSuggestionInput(
            history: [CardioSuggestionHistory(type: .cycle, durationMinutes: 30,
                                               moderateEquivalentMinutes: 30,
                                               isIndoor: true, start: now)],
            weeklyModerateEquivalentMinutes: 30, asOf: now)
        let encoded = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(CardioSuggestionInput.self, from: encoded)
        XCTAssertEqual(decoded, input)

        let result = try XCTUnwrap(CardioSuggestionGenerator.generate(input: input))
        XCTAssertFalse(result.citationIDs.isEmpty)
        XCTAssertTrue(result.citationIDs.allSatisfy { CitationRegistry.citation(forId: $0) != nil })
    }
}
