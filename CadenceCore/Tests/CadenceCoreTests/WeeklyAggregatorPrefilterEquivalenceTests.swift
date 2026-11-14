import XCTest
@testable import CadenceCore

final class WeeklyAggregatorPrefilterEquivalenceTests: XCTestCase {
    private let since = Date(timeIntervalSince1970: 1_000_000)
    private let profile = CardioIntensityProfile(maximumHR: 200, maximumHRSource: .userEntered)

    private func cardio(_ type: CardioType, offset: TimeInterval, minutes: Double) -> CardioWorkout {
        let start = since.addingTimeInterval(offset)
        return CardioWorkout(type: type, start: start, end: start.addingTimeInterval(minutes * 60))
    }

    private func strength(offset: TimeInterval, minutes: Double) -> WorkoutSession {
        let start = since.addingTimeInterval(offset)
        return WorkoutSession(title: "S", date: start, endedAt: start.addingTimeInterval(minutes * 60))
    }

    private func mixedWindowFixture() -> (cardio: [CardioWorkout], sessions: [WorkoutSession]) {
        (cardio: [cardio(.run, offset: -500_000, minutes: 40),
                  cardio(.walk, offset: 4_000, minutes: 20)],
         sessions: [strength(offset: -400_000, minutes: 60),
                    strength(offset: 5_000, minutes: 45)])
    }

    private func onOrAfter<T>(_ items: [T], date: (T) -> Date) -> [T] {
        items.filter { date($0) >= since }
    }

    func testWeeklyCardioAggregatorIsUnaffectedByPrefilteringToSinceBound() {
        let (c, s) = mixedWindowFixture()
        let full = WeeklyCardioAggregator.summarize(c, since: since, profile: profile, sessions: s)
        let prefiltered = WeeklyCardioAggregator.summarize(
            onOrAfter(c, date: \.start), since: since, profile: profile,
            sessions: onOrAfter(s, date: \.date))
        XCTAssertEqual(full, prefiltered)
    }

    func testWeeklyActivityDoseAggregatorIsUnaffectedByPrefilteringToSinceBound() {
        let (c, s) = mixedWindowFixture()
        let full = WeeklyActivityDoseAggregator.summarize(cardio: c, sessions: s, since: since, profile: profile)
        let prefiltered = WeeklyActivityDoseAggregator.summarize(
            cardio: onOrAfter(c, date: \.start), sessions: onOrAfter(s, date: \.date),
            since: since, profile: profile)
        XCTAssertEqual(full, prefiltered)
    }

    func testWeeklyStatsVolumeKgIsUnaffectedByPrefilteringToSinceBound() {
        let (_, s) = mixedWindowFixture()
        let full = WeeklyStats.volumeKg(s, since: since)
        let prefiltered = WeeklyStats.volumeKg(onOrAfter(s, date: \.date), since: since)
        XCTAssertEqual(full, prefiltered)
    }
}
