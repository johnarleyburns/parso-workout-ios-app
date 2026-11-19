import Foundation
import Testing
@testable import CadenceCore

struct StoreMigrationPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func healthAccessIsRequiredBeforeMigration() {
        let facts = StoreMigrationFacts(healthWriteAuthorized: false,
                                         autoSaveHealth: true, now: now)
        #expect(
            StoreMigrationPlanner.next(progress: .init(), facts: facts) ==
            .blocked(.healthAccessRequired))
    }

    @Test func snapshotMustExistBeforeCopy() {
        var progress = StoreMigrationProgress(completed: [.preflight])
        let facts = StoreMigrationFacts(healthWriteAuthorized: true,
                                        autoSaveHealth: true, now: now)
        #expect(
            StoreMigrationPlanner.next(progress: progress, facts: facts) ==
            .blocked(.snapshotRequired))

        progress.snapshotCreated = true
        progress.completed.insert(.snapshot)
        #expect(
            StoreMigrationPlanner.next(progress: progress, facts: facts) ==
            .run(.copy))
    }

    @Test func verificationMismatchStopsBeforeSwitch() {
        let completed: Set<StoreMigrationStep> = [.preflight, .snapshot, .copy,
                                                  .healthBackfill]
        let progress = StoreMigrationProgress(completed: completed,
                                              snapshotCreated: true)
        let facts = StoreMigrationFacts(healthWriteAuthorized: true,
                                        autoSaveHealth: true,
                                        verificationMismatches: ["owner sets"],
                                        now: now)
        #expect(
            StoreMigrationPlanner.next(progress: progress, facts: facts) ==
            .blocked(.verificationMismatch(["owner sets"])))
    }

    @Test func oldCopyMustAgeAndPurgeIsExplicit() {
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
            #expect(date == retainedUntil)
        } else {
            Issue.record("migration must retain the old copy for 30 days")
        }

        var agedFacts = facts
        agedFacts.now = retainedUntil
        #expect(
            StoreMigrationPlanner.next(progress: progress, facts: agedFacts) ==
            .blocked(.explicitPurgeConfirmationRequired))

        var confirmed = progress
        confirmed.purgeConfirmed = true
        #expect(
            StoreMigrationPlanner.next(progress: confirmed, facts: agedFacts) ==
            .run(.purgeOldCopy))
    }

    @Test func countMismatchesNamesOnlyDifferentCollections() {
        let old = StoreMigrationCounts(sessions: 2, ownerSets: 8, cardio: 1, assessments: 3)
        let new = StoreMigrationCounts(sessions: 2, ownerSets: 7, cardio: 2, assessments: 3)
        #expect(StoreMigrationPlanner.countMismatches(old: old, new: new) ==
                       ["owner sets", "cardio"])
    }
}
