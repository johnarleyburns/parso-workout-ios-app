import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct WatchTodayHomePresentationTests {
    @Test func syncedUnplannedIsReadyWithEmbeddedActions() {
        let p = WatchTodayHomePresentation(hero: .unplanned(synced: true))
        #expect(p == .ready(synced: true))
        #expect(p.showsEmbeddedStartActions)
        #expect(!p.showsQuickStartTiles)
        #expect(p.syncReminder == nil)
    }

    @Test func unsyncedUnplannedShowsQuietReminder() {
        let p = WatchTodayHomePresentation(hero: .unplanned(synced: false))
        #expect(p == .ready(synced: false))
        #expect(p.showsEmbeddedStartActions)
        #expect(!p.showsQuickStartTiles)
        #expect(p.syncReminder == "Sync your iPhone plan when convenient.")
    }

    @Test func restDayIsRestWithoutTiles() {
        let p = WatchTodayHomePresentation(hero: .restDay(advice: nil))
        #expect(p == .rest)
        #expect(!p.showsQuickStartTiles)
        #expect(!p.showsEmbeddedStartActions)
        #expect(p.syncReminder == nil)
    }

    @Test func otherHeroesAreStandardWithTiles() {
        let heroes: [WatchTodayHero] = [
            .resume(title: "t", detail: "d", startedAt: Date()),
            .planned(sessionID: "s", title: "t", exercises: [], minutes: nil, advice: nil),
            .plannedCardio(sessionID: "s", title: "t", detail: "", advice: nil),
        ]
        for hero in heroes {
            let p = WatchTodayHomePresentation(hero: hero)
            #expect(p == .standard)
            #expect(p.showsQuickStartTiles)
            #expect(!p.showsEmbeddedStartActions)
            #expect(p.syncReminder == nil)
        }
    }
}
