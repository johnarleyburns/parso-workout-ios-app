import XCTest
import SwiftData
@testable import CadenceCore

final class ImportedWorkoutKindTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    func testTraditionalStrengthPreservesKind() throws {
        let ctx = try makeContext()
        let ingested = IngestedWorkout(
            id: UUID(), type: .other, start: Date(), end: Date().addingTimeInterval(3600),
            source: .watch, importedKind: .traditionalStrength
        )
        let inserted = try WorkoutRepository.ingest([ingested], in: ctx)
        XCTAssertEqual(inserted, 1)

        let all = try WorkoutRepository.allCardio(ctx)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.importedWorkoutKind, .traditionalStrength)
        XCTAssertTrue(all.first?.importedWorkoutKind?.isStrength ?? false)
    }

    func testFunctionalStrengthPreservesKind() throws {
        let ctx = try makeContext()
        let ingested = IngestedWorkout(
            id: UUID(), type: .other, start: Date(), end: Date().addingTimeInterval(3600),
            source: .watch, importedKind: .functionalStrength
        )
        _ = try WorkoutRepository.ingest([ingested], in: ctx)

        let all = try WorkoutRepository.allCardio(ctx)
        XCTAssertEqual(all.first?.importedWorkoutKind, .functionalStrength)
    }

    func testDeduplicationByHKUUID() throws {
        let ctx = try makeContext()
        let uuid = UUID()
        let first = IngestedWorkout(
            id: uuid, type: .other, start: Date(), end: Date().addingTimeInterval(3600),
            source: .watch, importedKind: .traditionalStrength
        )
        let second = IngestedWorkout(
            id: uuid, type: .other, start: Date(), end: Date().addingTimeInterval(3600),
            source: .watch, importedKind: .traditionalStrength
        )
        _ = try WorkoutRepository.ingest([first], in: ctx)
        let inserted2 = try WorkoutRepository.ingest([second], in: ctx)
        XCTAssertEqual(inserted2, 0)

        let all = try WorkoutRepository.allCardio(ctx)
        XCTAssertEqual(all.count, 1)
    }

    func testNilImportedKindDoesNotBreak() throws {
        let ctx = try makeContext()
        let ingested = IngestedWorkout(
            id: UUID(), type: .run, start: Date(), end: Date().addingTimeInterval(3600),
            source: .watch, importedKind: nil
        )
        _ = try WorkoutRepository.ingest([ingested], in: ctx)

        let all = try WorkoutRepository.allCardio(ctx)
        XCTAssertEqual(all.count, 1)
        XCTAssertNil(all.first?.importedWorkoutKind)
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
