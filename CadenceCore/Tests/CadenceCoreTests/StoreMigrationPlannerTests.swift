import XCTest
@testable import CadenceCore

final class StoreMigrationPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testHealthAccessIsRequiredBeforeMigration() {
        let facts = StoreMigrationFacts(healthWriteAuthorized: false,
                                         autoSaveHealth: true, now: now)
        XCTAssertEqual(
            StoreMigrationPlanner.next(progress: .init(), facts: facts),
            .blocked(.healthAccessRequired))
    }

    func testSnapshotMustExistBeforeCopy() {
        var progress = StoreMigrationProgress(completed: [.preflight])
        let facts = StoreMigrationFacts(healthWriteAuthorized: true,
                                        autoSaveHealth: true, now: now)
        XCTAssertEqual(
            StoreMigrationPlanner.next(progress: progress, facts: facts),
            .blocked(.snapshotRequired))

        progress.snapshotCreated = true
        progress.completed.insert(.snapshot)
        XCTAssertEqual(
            StoreMigrationPlanner.next(progress: progress, facts: facts),
            .run(.copy))
    }

    func testVerificationMismatchStopsBeforeSwitch() {
        let completed: Set<StoreMigrationStep> = [.preflight, .snapshot, .copy,
                                                  .healthBackfill]
        let progress = StoreMigrationProgress(completed: completed,
                                              snapshotCreated: true)
        let facts = StoreMigrationFacts(healthWriteAuthorized: true,
                                        autoSaveHealth: true,
                                        verificationMismatches: ["owner sets"],
                                        now: now)
        XCTAssertEqual(
            StoreMigrationPlanner.next(progress: progress, facts: facts),
            .blocked(.verificationMismatch(["owner sets"])))
    }

    func testOldCopyMustAgeAndPurgeIsExplicit() {
        let retainedUntil = now.addingTimeInterval(30 * 24 * 60 * 60)
        let completed: Set<StoreMigrationStep> = [.preflight, .snapshot, .copy,
                                                  .healthBackfill, .verify,
                                                  .switchStore, .retainOldCopy]
        let progress = StoreMigrationProgress(completed: completed,
                                              snapshotCreated: true,
                                              oldCopyRetainedUntil: retainedUntil)
        let facts = StoreMigrationFacts(healthWriteAuthorized: true,
                                        autoSaveHealth: true, now: now)
        if case .blocked(.retentionNotElapsed(let date)) =
            StoreMigrationPlanner.next(progress: progress, facts: facts) {
            XCTAssertEqual(date, retainedUntil)
        } else {
            XCTFail("migration must retain the old copy for 30 days")
        }

        var agedFacts = facts
        agedFacts.now = retainedUntil
        XCTAssertEqual(
            StoreMigrationPlanner.next(progress: progress, facts: agedFacts),
            .blocked(.explicitPurgeConfirmationRequired))

        var confirmed = progress
        confirmed.purgeConfirmed = true
        XCTAssertEqual(
            StoreMigrationPlanner.next(progress: confirmed, facts: agedFacts),
            .run(.purgeOldCopy))
    }

    func testCountMismatchesNamesOnlyDifferentCollections() {
        let old = StoreMigrationCounts(sessions: 2, ownerSets: 8, cardio: 1, assessments: 3)
        let new = StoreMigrationCounts(sessions: 2, ownerSets: 7, cardio: 2, assessments: 3)
        XCTAssertEqual(StoreMigrationPlanner.countMismatches(old: old, new: new),
                       ["owner sets", "cardio"])
    }
}
