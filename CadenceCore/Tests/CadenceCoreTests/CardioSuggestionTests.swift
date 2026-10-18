import XCTest
@testable import CadenceCore

final class CardioSuggestionTests: XCTestCase {
    // Wednesday 2023-11-15 in UTC; Monday-start week leaves 5 days incl. today.
    private let now = Date(timeIntervalSince1970: 1_700_049_600)
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }

    private func input(weekly: Double, target: Double = 150,
                       excluded: Set<String> = [], skipped: Set<String> = []) -> CardioSuggestionInput {
        CardioSuggestionInput(weeklyModerateEquivalentMinutes: weekly, weeklyTargetMinutes: target,
                              asOf: now, excludedProtocolIDs: excluded, skippedProtocolIDs: skipped)
    }

    func testAlwaysSuggestsLibraryProtocolWithResolvableCitations() throws {
        let result = try XCTUnwrap(CardioSuggestionGenerator.generate(input: input(weekly: 0), calendar: calendar))
        XCTAssertTrue(result.isInterval)
        let id = try XCTUnwrap(result.protocolID)
        XCTAssertNotNil(HIITProtocol.find(id: id))
        XCTAssertFalse(result.citationIDs.isEmpty)
        XCTAssertTrue(result.citationIDs.allSatisfy { CitationRegistry.citation(forId: $0) != nil })
    }

    func testGillenLibraryEntryAndGates() throws {
        let g = try XCTUnwrap(HIITProtocol.find(id: "gillen"))
        XCTAssertEqual(g.name, "Gillen")
        XCTAssertEqual(g.subtitle, "3 × 20s all-out / 2 min")
        XCTAssertNotNil(g.modalityCue)
        XCTAssertEqual(g.citationIDs, ["gillenSIT2016"])
        XCTAssertEqual(g.totalMinutes, 10, accuracy: 0.001)
        let others = Set(HIITProtocol.library.map(\.id)).subtracting(["gillen"])
        let onlyGillen = CardioSuggestionInput(weeklyModerateEquivalentMinutes: 0, experience: .beginner,
                                               asOf: input(weekly: 0).asOf, excludedProtocolIDs: others)
        XCTAssertNil(CardioSuggestionGenerator.generate(input: onlyGillen, calendar: calendar))
        let adv = CardioSuggestionInput(weeklyModerateEquivalentMinutes: 0, experience: .intermediate,
                                        asOf: onlyGillen.asOf, excludedProtocolIDs: others)
        XCTAssertEqual(CardioSuggestionGenerator.generate(input: adv, calendar: calendar)?.protocolID, "gillen")
        let excluded = CardioSuggestionInput(weeklyModerateEquivalentMinutes: 0, experience: .intermediate,
                                             asOf: onlyGillen.asOf, excludedProtocolIDs: others.union(["gillen"]))
        XCTAssertNil(CardioSuggestionGenerator.generate(input: excluded, calendar: calendar))
    }

    func testRequiredMinutesPerDayDividesRemainingByDaysLeftIncludingToday() {
        let perDay = CardioSuggestionGenerator.requiredMinutesPerDay(
            input: input(weekly: 50), calendar: calendar)
        XCTAssertEqual(perDay, 20, accuracy: 0.001)
    }

    func testSmallNeedPicksShortestProtocolAndLargeNeedPicksMoreCredit() throws {
        let small = try XCTUnwrap(CardioSuggestionGenerator.generate(input: input(weekly: 149), calendar: calendar))
        XCTAssertEqual(small.protocolID, "rehit")
        let large = try XCTUnwrap(CardioSuggestionGenerator.generate(input: input(weekly: 0), calendar: calendar))
        let picked = try XCTUnwrap(HIITProtocol.find(id: try XCTUnwrap(large.protocolID)))
        XCTAssertGreaterThanOrEqual(picked.moderateEquivalentMinutes, 30)
        let shorter = HIITProtocol.library.filter {
            $0.totalMinutes < picked.totalMinutes && $0.moderateEquivalentMinutes >= 30
        }
        XCTAssertTrue(shorter.isEmpty)
    }

    func testSkippedAndExcludedProtocolsAreNeverSuggested() throws {
        let first = try XCTUnwrap(CardioSuggestionGenerator.generate(input: input(weekly: 149), calendar: calendar))
        let next = try XCTUnwrap(CardioSuggestionGenerator.generate(
            input: input(weekly: 149, skipped: [try XCTUnwrap(first.protocolID)]), calendar: calendar))
        XCTAssertNotEqual(next.protocolID, first.protocolID)
        let third = try XCTUnwrap(CardioSuggestionGenerator.generate(
            input: input(weekly: 149, excluded: [try XCTUnwrap(first.protocolID)],
                         skipped: [try XCTUnwrap(next.protocolID)]), calendar: calendar))
        XCTAssertFalse([first.protocolID, next.protocolID].contains(third.protocolID))
    }

    func testAllProtocolsBlockedReturnsNil() {
        let all = Set(HIITProtocol.library.map(\.id))
        XCTAssertNil(CardioSuggestionGenerator.generate(input: input(weekly: 0, skipped: all), calendar: calendar))
    }

    func testValueRoundTrip() throws {
        let i = input(weekly: 30, excluded: ["tabata"], skipped: ["sit"])
        let decoded = try JSONDecoder().decode(CardioSuggestionInput.self, from: JSONEncoder().encode(i))
        XCTAssertEqual(decoded, i)
    }
}
