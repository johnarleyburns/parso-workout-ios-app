import Foundation
import Testing
@testable import CadenceCore

struct CardioSuggestionTests {
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

    @Test func alwaysSuggestsLibraryProtocolWithResolvableCitations() throws {
        let result = try #require(CardioSuggestionGenerator.generate(input: input(weekly: 0), calendar: calendar))
        #expect(result.isInterval)
        let id = try #require(result.protocolID)
        #expect(HIITProtocol.find(id: id) != nil)
        #expect(!result.citationIDs.isEmpty)
        #expect(result.citationIDs.allSatisfy { CitationRegistry.citation(forId: $0) != nil })
    }

    @Test func gillenLibraryEntryAndGates() throws {
        let g = try #require(HIITProtocol.find(id: "gillen"))
        #expect(g.name == "Gillen")
        #expect(g.subtitle == "3 × 20s all-out / 2 min")
        #expect(g.modalityCue != nil)
        #expect(g.citationIDs == ["gillenSIT2016"])
        #expect(abs(g.totalMinutes - 10) <= 0.001)
        let others = Set(HIITProtocol.library.map(\.id)).subtracting(["gillen"])
        let onlyGillen = CardioSuggestionInput(weeklyModerateEquivalentMinutes: 0, experience: .beginner,
                                               asOf: input(weekly: 0).asOf, excludedProtocolIDs: others)
        #expect(CardioSuggestionGenerator.generate(input: onlyGillen, calendar: calendar) == nil)
        let adv = CardioSuggestionInput(weeklyModerateEquivalentMinutes: 0, experience: .intermediate,
                                        asOf: onlyGillen.asOf, excludedProtocolIDs: others)
        #expect(CardioSuggestionGenerator.generate(input: adv, calendar: calendar)?.protocolID == "gillen")
        let excluded = CardioSuggestionInput(weeklyModerateEquivalentMinutes: 0, experience: .intermediate,
                                             asOf: onlyGillen.asOf, excludedProtocolIDs: others.union(["gillen"]))
        #expect(CardioSuggestionGenerator.generate(input: excluded, calendar: calendar) == nil)
    }

    @Test func requiredMinutesPerDayDividesRemainingByDaysLeftIncludingToday() {
        let perDay = CardioSuggestionGenerator.requiredMinutesPerDay(
            input: input(weekly: 50), calendar: calendar)
        #expect(abs(perDay - 20) <= 0.001)
    }

    @Test func smallNeedPicksShortestProtocolAndLargeNeedPicksMoreCredit() throws {
        let small = try #require(CardioSuggestionGenerator.generate(input: input(weekly: 149), calendar: calendar))
        #expect(small.protocolID == "rehit")
        let large = try #require(CardioSuggestionGenerator.generate(input: input(weekly: 0), calendar: calendar))
        let largeProtocolID = try #require(large.protocolID)
        let picked = try #require(HIITProtocol.find(id: largeProtocolID))
        #expect(picked.moderateEquivalentMinutes >= 30)
        let shorter = HIITProtocol.library.filter {
            $0.totalMinutes < picked.totalMinutes && $0.moderateEquivalentMinutes >= 30
        }
        #expect(shorter.isEmpty)
    }

    @Test func skippedAndExcludedProtocolsAreNeverSuggested() throws {
        let first = try #require(CardioSuggestionGenerator.generate(input: input(weekly: 149), calendar: calendar))
        let firstProtocolID = try #require(first.protocolID)
        let next = try #require(CardioSuggestionGenerator.generate(
            input: input(weekly: 149, skipped: [firstProtocolID]), calendar: calendar))
        #expect(next.protocolID != first.protocolID)
        let nextProtocolID = try #require(next.protocolID)
        let third = try #require(CardioSuggestionGenerator.generate(
            input: input(weekly: 149, excluded: [firstProtocolID],
                         skipped: [nextProtocolID]), calendar: calendar))
        #expect(![first.protocolID, next.protocolID].contains(third.protocolID))
    }

    @Test func allProtocolsBlockedReturnsNil() {
        let all = Set(HIITProtocol.library.map(\.id))
        #expect(CardioSuggestionGenerator.generate(input: input(weekly: 0, skipped: all), calendar: calendar) == nil)
    }

    @Test func valueRoundTrip() throws {
        let i = input(weekly: 30, excluded: ["tabata"], skipped: ["sit"])
        let decoded = try JSONDecoder().decode(CardioSuggestionInput.self, from: JSONEncoder().encode(i))
        #expect(decoded == i)
    }
}
