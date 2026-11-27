import Foundation
import Testing
@testable import CadenceCore

struct EmptyDuplicateCleanupTests {
    private func session(_ minutes: Int, sets: Bool, deleted: Bool = false) -> EmptyDuplicateCleanup.Session {
        EmptyDuplicateCleanup.Session(id: UUID(),
                                      date: Date(timeIntervalSince1970: 1_700_000_000)
                                          .addingTimeInterval(TimeInterval(minutes * 60)),
                                      hasSets: sets,
                                      isDeleted: deleted)
    }

    @Test func hidesAnEmptyTwinOfASessionWithSets() {
        let real = session(0, sets: true)
        let twin = session(4, sets: false)
        #expect(EmptyDuplicateCleanup.duplicateIDs(in: [real, twin]) == [twin.id])
    }

    @Test func keepsAnEmptySessionThatIsNotNearARealOne() {
        let real = session(0, sets: true)
        let unrelated = session(90, sets: false)
        #expect(EmptyDuplicateCleanup.duplicateIDs(in: [real, unrelated]).isEmpty)
    }

    @Test func neverHidesSessionsWithSetsOrDeletedRows() {
        let real = session(0, sets: true)
        let another = session(5, sets: true)
        let deletedTwin = session(2, sets: false, deleted: true)
        #expect(EmptyDuplicateCleanup.duplicateIDs(in: [real, another, deletedTwin]).isEmpty)
    }

    @Test func hidesNothingWhenNoSessionHasSets() {
        #expect(EmptyDuplicateCleanup.duplicateIDs(in: [session(0, sets: false),
                                                        session(5, sets: false)]).isEmpty)
    }
}
