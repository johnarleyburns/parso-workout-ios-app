import XCTest
import SwiftData
@testable import CadenceCore

final class ImportedWorkoutKindTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    func testAutoImportRejectsWatchStrength() throws {
        let ctx = try makeContext()
        let ingested = IngestedWorkout(
            id: UUID(), type: .other, start: Date(), end: Date().addingTimeInterval(3600),
            source: .watch, importedKind: .traditionalStrength
        )
        let inserted = try WorkoutRepository.ingest([ingested], in: ctx)
        XCTAssertEqual(inserted, 0)

        let all = try WorkoutRepository.allCardio(ctx)
        XCTAssertTrue(all.isEmpty)
    }

    func testAutoImportRejectsIPhoneOrigin() throws {
        let ctx = try makeContext()
        let ingested = IngestedWorkout(
            id: UUID(), type: .run, start: Date(), end: Date().addingTimeInterval(1800),
            source: .iphone, importedKind: .running
        )
        XCTAssertEqual(try WorkoutRepository.ingest([ingested], in: ctx), 0)

        let all = try WorkoutRepository.allCardio(ctx)
        XCTAssertTrue(all.isEmpty)
    }

    func testAutoImportRejectsOtherAndAmbiguousKind() throws {
        let ctx = try makeContext()
        let other = IngestedWorkout(
            id: UUID(), type: .other, start: Date(), end: Date().addingTimeInterval(1200),
            source: .watch, importedKind: .other
        )
        let ambiguous = IngestedWorkout(
            id: UUID(), type: .run, start: Date(), end: Date().addingTimeInterval(1200),
            source: .watch, importedKind: nil
        )

        XCTAssertEqual(try WorkoutRepository.ingest([other, ambiguous], in: ctx), 0)
        XCTAssertTrue(try WorkoutRepository.allCardio(ctx).isEmpty)
    }

    func testDeduplicationByHKUUID() throws {
        let ctx = try makeContext()
        let uuid = UUID()
        let first = IngestedWorkout(
            id: uuid, type: .run, start: Date(), end: Date().addingTimeInterval(3600),
            source: .watch, importedKind: .running
        )
        let second = IngestedWorkout(
            id: uuid, type: .run, start: Date(), end: Date().addingTimeInterval(3600),
            source: .watch, importedKind: .running
        )
        _ = try WorkoutRepository.ingest([first], in: ctx)
        let inserted2 = try WorkoutRepository.ingest([second], in: ctx)
        XCTAssertEqual(inserted2, 0)

        let all = try WorkoutRepository.allCardio(ctx)
        XCTAssertEqual(all.count, 1)
    }

    func testAutoImportAcceptsWatchCardioKinds() throws {
        let ctx = try makeContext()
        let accepted: [IngestedWorkout] = [
            IngestedWorkout(id: UUID(), type: .run, start: Date(), end: Date().addingTimeInterval(600),
                            source: .watch, importedKind: .running),
            IngestedWorkout(id: UUID(), type: .walk, start: Date(), end: Date().addingTimeInterval(600),
                            source: .watch, importedKind: .walking),
            IngestedWorkout(id: UUID(), type: .cycle, start: Date(), end: Date().addingTimeInterval(600),
                            source: .watch, importedKind: .cycling),
            IngestedWorkout(id: UUID(), type: .swim, start: Date(), end: Date().addingTimeInterval(600),
                            source: .watch, importedKind: .swimming),
            IngestedWorkout(id: UUID(), type: .rowing, start: Date(), end: Date().addingTimeInterval(600),
                            source: .watch, importedKind: .rowing),
            IngestedWorkout(id: UUID(), type: .hiit, start: Date(), end: Date().addingTimeInterval(600),
                            source: .watch, importedKind: .hiit),
            IngestedWorkout(id: UUID(), type: .boxing, start: Date(), end: Date().addingTimeInterval(600),
                            source: .watch, importedKind: .boxing)
        ]

        XCTAssertEqual(try WorkoutRepository.ingest(accepted, in: ctx), accepted.count)
        let all = try WorkoutRepository.allCardio(ctx)
        XCTAssertEqual(all.count, accepted.count)
    }

    func testRunningWalkingSwimmingMappedCorrectly() {
        let running = IngestedWorkout(
            id: UUID(), type: .run, start: Date(), end: Date().addingTimeInterval(3600),
            source: .watch, importedKind: .running
        )
        let walking = IngestedWorkout(
            id: UUID(), type: .walk, start: Date(), end: Date().addingTimeInterval(3600),
            source: .watch, importedKind: .walking
        )
        let swim = IngestedWorkout(
            id: UUID(), type: .swim, start: Date(), end: Date().addingTimeInterval(3600),
            source: .watch, importedKind: .swimming
        )

        XCTAssertEqual(running.importedKind, .running)
        XCTAssertEqual(walking.importedKind, .walking)
        XCTAssertEqual(swim.importedKind, .swimming)
    }
}
