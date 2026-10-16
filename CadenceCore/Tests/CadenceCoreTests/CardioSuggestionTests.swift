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

    func testIntervalHabitSurfacesEvenWhenLatestSessionWasARun() {
        var history = [CardioSuggestionHistory(
            type: .run, durationMinutes: 30, moderateEquivalentMinutes: 30,
            start: now)]
        history += (1...3).map { index in
            CardioSuggestionHistory(
                type: .hiit, durationMinutes: 25, moderateEquivalentMinutes: 50,
                intensity: .veryHard, isInterval: true,
                start: now.addingTimeInterval(TimeInterval(-index * 3 * 86_400)))
        }
        let result = CardioSuggestionGenerator.generate(
            input: CardioSuggestionInput(history: history,
                                         weeklyModerateEquivalentMinutes: 0,
                                         experience: .intermediate, asOf: now))

        XCTAssertEqual(result?.type, .hiit)
        XCTAssertEqual(result?.intensity, .interval)
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

    private func steadyHistory(_ type: CardioType, count: Int = 4) -> [CardioSuggestionHistory] {
        (0..<count).map { index in
            CardioSuggestionHistory(
                type: type, durationMinutes: 40, moderateEquivalentMinutes: 40,
                intensity: .moderate,
                start: now.addingTimeInterval(TimeInterval(-(index + 1) * 86_400)))
        }
    }

    func testNoRecentIntervalsSuggestsNorwegian4x4OnPreferredModality() throws {
        let result = try XCTUnwrap(CardioSuggestionGenerator.generate(
            input: CardioSuggestionInput(history: steadyHistory(.swim),
                                         weeklyModerateEquivalentMinutes: 60, asOf: now)))
        XCTAssertEqual(result.type, .swim)
        XCTAssertTrue(result.isInterval)
        XCTAssertEqual(result.intervalRounds, 4)
        XCTAssertEqual(result.intervalWorkSeconds, 240)
        XCTAssertNotNil(result.observation)
        XCTAssertTrue(result.citationIDs.contains("hiitVo2max"))
        XCTAssertTrue(result.citationIDs.contains("gillenSIT2016"))
        XCTAssertTrue(result.citationIDs.allSatisfy { CitationRegistry.citation(forId: $0) != nil })
    }

    func testWalkingHistoryNeverReceivesIntervalsOnWalk() throws {
        let result = try XCTUnwrap(CardioSuggestionGenerator.generate(
            input: CardioSuggestionInput(history: steadyHistory(.walk),
                                         weeklyModerateEquivalentMinutes: 60, asOf: now)))
        XCTAssertFalse(result.isInterval)
    }

    func testExcludedTypeIsNeverSuggested() throws {
        let result = try XCTUnwrap(CardioSuggestionGenerator.generate(
            input: CardioSuggestionInput(history: steadyHistory(.run),
                                         weeklyModerateEquivalentMinutes: 60, asOf: now,
                                         excludedTypes: [.run])))
        XCTAssertNotEqual(result.type, .run)
    }

    func testEmptyHistoryFallbackSkipsExcludedAndAllExcludedReturnsNil() {
        let skipped = CardioSuggestionGenerator.generate(
            input: CardioSuggestionInput(weeklyModerateEquivalentMinutes: 0, asOf: now,
                                         excludedTypes: [.run]))
        XCTAssertEqual(skipped?.type, .walk)
        let none = CardioSuggestionGenerator.generate(
            input: CardioSuggestionInput(
                weeklyModerateEquivalentMinutes: 0, asOf: now,
                excludedTypes: Set(CardioType.allCases)))
        XCTAssertNil(none)
    }
}
