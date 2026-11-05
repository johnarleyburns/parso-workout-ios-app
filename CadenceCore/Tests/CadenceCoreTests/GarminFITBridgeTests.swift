import XCTest
import SwiftData
@testable import CadenceCore

/// Deterministic, headless coverage of the Garmin FIT bridge (issue #530).
/// Uses FIT bytes produced by DB++ v1.18.2's `GarminFITAdapter`; no network,
/// file picker, simulator, or wall-clock dependence.
@MainActor
final class GarminFITBridgeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_100_000)

    private func makeContext(_ dir: URL? = nil) throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: dir == nil, cloudKitEnabled: false,
                                                            storeURL: dir?.appendingPathComponent("fit.store"))
        return ModelContext(container)
    }

    @discardableResult
    private func seed(_ context: ModelContext, id: UUID = UUID(), long: Bool = false) -> WorkoutSession {
        let session = WorkoutSession(id: id, title: "Push", date: start, endedAt: start.addingTimeInterval(3600),
                                     notes: "Felt strong — café ☕")
        let bench = Exercise(name: "Barbell Bench Press", sourceExerciseID: "Barbell_Bench_Press_-_Medium_Grip")
        let custom = Exercise(name: "Żurek Carry 横", isCustom: true)
        context.insert(session); context.insert(bench); context.insert(custom)
        let count = long ? 40 : 2
        for i in 0..<count {
            context.insert(SetEntry(weight: 60 + Double(i), reps: 8, order: i, isWarmup: i == 0, rpe: i == 1 ? 8 : nil,
                                    note: i == 1 ? "paused ñ" : nil, completedAt: start.addingTimeInterval(60),
                                    session: session, exercise: bench))
        }
        context.insert(SetEntry(weight: 20, reps: 12, order: count, completedAt: start.addingTimeInterval(900),
                                session: session, exercise: custom))
        return session
    }

    func testExportBlockersAndFilename() throws {
        let context = try makeContext()
        let open = WorkoutSession(title: "x", date: start)
        context.insert(open)
        XCTAssertEqual(GarminFITBridge.exportBlockers(for: open), .notFinished)
        XCTAssertThrowsError(try GarminFITBridge.export(session: open)) {
            XCTAssertEqual($0 as? GarminFITBridge.Failure, .invalidWorkout(.notFinished))
        }
        let empty = WorkoutSession(title: "x", date: start, endedAt: start.addingTimeInterval(5))
        context.insert(empty)
        XCTAssertEqual(GarminFITBridge.exportBlockers(for: empty), .noCompletedSets)
        let good = seed(context)
        XCTAssertNil(GarminFITBridge.exportBlockers(for: good))
        XCTAssertTrue(GarminFITBridge.filename(for: good).hasSuffix(".fit"))
        XCTAssertTrue(GarminFITBridge.filename(for: good).contains(good.id.uuidString.prefix(8).lowercased()))
    }

    func testExportedFileIsFITAndRoundTripsLosslessly() throws {
        let context = try makeContext()
        let session = seed(context)
        let file = try GarminFITBridge.export(session: session)
        XCTAssertEqual(Array(file.data[8..<12]), Array(".FIT".utf8))

        let preview = try GarminFITBridge.preview(data: file.data, filename: file.filename)
        XCTAssertEqual(preview.fidelity, .lossless)
        XCTAssertEqual(preview.sessionID, session.id)
        XCTAssertEqual(preview.exerciseCount, 2)
        XCTAssertEqual(preview.setCount, 3)
        XCTAssertEqual(preview.start.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(preview.sourceFilename, file.filename)

        let target = try makeContext()
        let receipt = try XCTUnwrap(try GarminFITBridge.apply(preview, to: target))
        XCTAssertEqual(receipt.importedSessionID, session.id)
        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(restored.id, session.id)
        XCTAssertEqual(restored.notes, "Felt strong — café ☕")
        XCTAssertEqual(restored.endedAt, session.endedAt)
        let sets = restored.orderedSets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets[0].isWarmup)
        XCTAssertEqual(sets[1].rpe, 8)
        XCTAssertEqual(sets[1].note, "paused ñ")
        XCTAssertEqual(sets[1].weight, 61, accuracy: 0.0001)
        XCTAssertEqual(sets[1].exercise?.sourceExerciseID, "Barbell_Bench_Press_-_Medium_Grip")
        XCTAssertEqual(sets[2].exercise?.name, "Żurek Carry 横")
        XCTAssertEqual(sets[2].exercise?.isCustom, true)
        XCTAssertEqual(sets[2].reps, 12)
    }

    func testMultiChunkSidecarRoundTrips() throws {
        let context = try makeContext()
        let session = seed(context, long: true)
        let file = try GarminFITBridge.export(session: session)
        let preview = try GarminFITBridge.preview(data: file.data, filename: file.filename)
        XCTAssertEqual(preview.setCount, 41)
    }

    func testReloadAfterFreshContainerRestoresSameWorkout() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try makeContext()
        let session = seed(source)
        let file = try GarminFITBridge.export(session: session)
        do {
            let context = try makeContext(dir)
            let preview = try GarminFITBridge.preview(data: file.data, filename: file.filename)
            try GarminFITBridge.apply(preview, to: context)
        }
        let reopened = try makeContext(dir)
        let all = try reopened.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(all.map(\.id), [session.id])
        XCTAssertEqual(all.first?.orderedSets.count, 3)
    }

    func testMalformedAndNonFITInputWritesNothing() throws {
        let context = try makeContext()
        let session = seed(context)
        let file = try GarminFITBridge.export(session: session)
        XCTAssertThrowsError(try GarminFITBridge.preview(data: Data("hello world, not fit".utf8), filename: "a.fit")) {
            XCTAssertEqual($0 as? GarminFITBridge.Failure, .notFIT)
        }
        XCTAssertThrowsError(try GarminFITBridge.preview(data: Data(), filename: "a.fit"))
        let truncated = file.data.prefix(file.data.count / 2)
        XCTAssertThrowsError(try GarminFITBridge.preview(data: Data(truncated), filename: "a.fit"))
        var big = file.data
        big.append(Data(count: GarminFITBridge.maxFileBytes))
        XCTAssertThrowsError(try GarminFITBridge.preview(data: big, filename: "a.fit")) {
            XCTAssertEqual($0 as? GarminFITBridge.Failure, .tooLarge)
        }
        let target = try makeContext()
        XCTAssertEqual(try target.fetch(FetchDescriptor<WorkoutSession>()).count, 0)
    }

    func testNativeOnlyFITRequiresSidecarAndWritesNothing() throws {
        let data = Self.nativeOnlyFIT()
        XCTAssertThrowsError(try GarminFITBridge.preview(data: data, filename: "garmin.fit")) {
            XCTAssertEqual($0 as? GarminFITBridge.Failure, .sidecarRequired)
        }
        let context = try makeContext()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetEntry>()).count, 0)
    }

    func testDuplicateDecisions() throws {
        let context = try makeContext()
        let session = seed(context)
        try context.save()
        let preview = try GarminFITBridge.preview(data: try GarminFITBridge.export(session: session).data,
                                                  filename: "dup.fit")
        XCTAssertNotNil(GarminFITBridge.existingSession(for: preview, in: context))

        XCTAssertNil(try GarminFITBridge.apply(preview, to: context, duplicate: .cancel))
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)

        let both = try XCTUnwrap(try GarminFITBridge.apply(preview, to: context, duplicate: .keepBoth))
        XCTAssertNotEqual(both.importedSessionID, session.id)
        let all = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.first { $0.id == both.importedSessionID }?.notes?.contains(session.id.uuidString) == true)

        try GarminFITBridge.undo(both, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)

        let replaced = try XCTUnwrap(try GarminFITBridge.apply(preview, to: context, duplicate: .replace))
        XCTAssertEqual(replaced.replacedSessionID, session.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
        XCTAssertThrowsError(try GarminFITBridge.undo(replaced, in: context))
    }

    func testInvalidSidecarIsRejected() throws {
        XCTAssertThrowsError(try GarminFITBridge.parse(Data("{\"schemaVersion\":\"0.3.0\"}".utf8))) {
            XCTAssertEqual($0 as? GarminFITBridge.Failure, .invalidSidecar)
        }
    }

    /// Minimal valid FIT with a single File Id message and no sessions.
    static func nativeOnlyFIT() -> Data {
        let body: [UInt8] = [0x40, 0, 0, 0, 0, 1, 0, 1, 0x00, 0x00, 4]
        var header: [UInt8] = [14, 0x10, 0x34, 0x08, UInt8(body.count), 0, 0, 0] + Array(".FIT".utf8) + [0, 0]
        header += body
        let crc = fitCRC(header)
        return Data(header + [UInt8(crc & 0xFF), UInt8(crc >> 8)])
    }

    private static func fitCRC(_ bytes: [UInt8]) -> UInt16 {
        let table: [UInt16] = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
                               0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]
        var crc: UInt16 = 0
        for byte in bytes {
            var tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int(byte & 0xF)]
            tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int((byte >> 4) & 0xF)]
        }
        return crc
    }
}
