import XCTest
@testable import CadenceFeatures

final class WatchTodayHomePresentationTests: XCTestCase {
    func testSyncedUnplannedIsReadyWithEmbeddedActions() {
        let p = WatchTodayHomePresentation(hero: .unplanned(synced: true))
        XCTAssertEqual(p, .ready(synced: true))
        XCTAssertTrue(p.showsEmbeddedStartActions)
        XCTAssertFalse(p.showsQuickStartTiles)
        XCTAssertNil(p.syncReminder)
    }

    func testUnsyncedUnplannedShowsQuietReminder() {
        let p = WatchTodayHomePresentation(hero: .unplanned(synced: false))
        XCTAssertEqual(p, .ready(synced: false))
        XCTAssertTrue(p.showsEmbeddedStartActions)
        XCTAssertFalse(p.showsQuickStartTiles)
        XCTAssertEqual(p.syncReminder, "Sync your iPhone plan when convenient.")
    }

    func testRestDayIsRestWithoutTiles() {
        let p = WatchTodayHomePresentation(hero: .restDay(advice: nil))
        XCTAssertEqual(p, .rest)
        XCTAssertFalse(p.showsQuickStartTiles)
        XCTAssertFalse(p.showsEmbeddedStartActions)
        XCTAssertNil(p.syncReminder)
    }

    func testOtherHeroesAreStandardWithTiles() {
        let heroes: [WatchTodayHero] = [
            .resume(title: "t", detail: "d", startedAt: Date()),
            .planned(sessionID: "s", title: "t", exercises: [], minutes: nil, advice: nil),
            .plannedCardio(sessionID: "s", title: "t", detail: "", advice: nil),
        ]
        for hero in heroes {
            let p = WatchTodayHomePresentation(hero: hero)
            XCTAssertEqual(p, .standard)
            XCTAssertTrue(p.showsQuickStartTiles)
            XCTAssertFalse(p.showsEmbeddedStartActions)
            XCTAssertNil(p.syncReminder)
        }
    }
}
