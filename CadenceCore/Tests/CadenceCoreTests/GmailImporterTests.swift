import XCTest
@testable import CadenceCore

final class GmailImporterTests: XCTestCase {

    func testParsesHeaderWithDateAndSetsReps() {
        let text = """
        # Push Day 2024-01-15
        Bench Press 100kg 3x5
        Overhead Press 60 5,5,4
        """
        let result = GmailImporter.parse(text)
        XCTAssertEqual(result.sessions.count, 1)
        let session = result.sessions[0]
        XCTAssertEqual(session.title, "Push Day")
        XCTAssertNotNil(session.date)
        XCTAssertEqual(session.exercises.count, 2)

        let bench = session.exercises[0]
        XCTAssertEqual(bench.name, "Bench Press")
        XCTAssertEqual(bench.sets.count, 3)
        XCTAssertEqual(bench.sets.allSatisfy { $0.reps == 5 }, true)
        XCTAssertEqual(bench.sets[0].weightKg, 100, accuracy: 1e-6)

        let ohp = session.exercises[1]
        XCTAssertEqual(ohp.sets.map(\.reps), [5, 5, 4])
    }

    func testPoundsConvertToKg() {
        let result = GmailImporter.parse("Deadlift 225lb 5x1")
        let set = result.sessions[0].exercises[0].sets[0]
        XCTAssertEqual(set.weightKg, WorkoutMath.lbToKg(225), accuracy: 1e-6)
    }

    func testPRMarkersAreStripped() {
        let result = GmailImporter.parse("Incline DB Press 30kg 8x3 PR")
        XCTAssertTrue(result.issues.isEmpty)
        let ex = result.sessions[0].exercises[0]
        XCTAssertEqual(ex.name, "Incline DB Press")
        XCTAssertEqual(ex.sets.count, 8)
        XCTAssertEqual(ex.sets[0].reps, 3)
    }

    func testMultipleSessions() {
        let text = """
        # Push 2024-01-15
        Bench Press 100 3x5

        # Pull 2024-01-17
        Deadlift 180 5x1
        """
        let result = GmailImporter.parse(text)
        XCTAssertEqual(result.sessions.count, 2)
        XCTAssertEqual(result.sessions[1].title, "Pull")
    }

    func testUnparseableLineFlaggedRestImported() {
        let text = """
        # Day
        Bench Press 100 3x5
        this line is gibberish
        Squat 140 5x3
        """
        let result = GmailImporter.parse(text)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues[0].text, "this line is gibberish")
        XCTAssertEqual(result.sessions[0].exercises.count, 2)
    }

    func testSetsRepsParsing() {
        XCTAssertEqual(GmailImporter.parseSetsReps("3x5"), [5, 5, 5])
        XCTAssertEqual(GmailImporter.parseSetsReps("5x1"), [1, 1, 1, 1, 1])
        XCTAssertEqual(GmailImporter.parseSetsReps("5,5,4"), [5, 5, 4])
        XCTAssertEqual(GmailImporter.parseSetsReps("8"), [8])
        XCTAssertNil(GmailImporter.parseSetsReps("abc"))
        XCTAssertNil(GmailImporter.parseSetsReps("3x"))
    }

    func testWeightParsing() {
        XCTAssertEqual(GmailImporter.parseWeight("100", defaultUnit: .kilograms), 100)
        XCTAssertEqual(GmailImporter.parseWeight("100kg", defaultUnit: .pounds), 100)
        XCTAssertEqual(GmailImporter.parseWeight("225lb", defaultUnit: .kilograms)!,
                       WorkoutMath.lbToKg(225), accuracy: 1e-6)
        XCTAssertNil(GmailImporter.parseWeight("heavy", defaultUnit: .kilograms))
    }

    func testBareDateLineStartsSession() {
        let text = """
        2024-03-01
        Squat 140 5x5
        """
        let result = GmailImporter.parse(text)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertNotNil(result.sessions[0].date)
        XCTAssertEqual(result.sessions[0].exercises.count, 1)
    }

    func testTotalSetsCount() {
        let result = GmailImporter.parse("# D\nBench 100 3x5\nSquat 140 5x3")
        XCTAssertEqual(result.totalSets, 8)
    }
}
