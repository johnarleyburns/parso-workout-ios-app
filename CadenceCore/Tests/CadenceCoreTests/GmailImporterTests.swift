import Testing
@testable import CadenceCore

struct GmailImporterTests {

    @Test func parsesHeaderWithDateAndSetsReps() {
        let text = """
        # Push Day 2024-01-15
        Bench Press 100kg 3x5
        Overhead Press 60 5,5,4
        """
        let result = GmailImporter.parse(text)
        #expect(result.sessions.count == 1)
        let session = result.sessions[0]
        #expect(session.title == "Push Day")
        #expect(session.date != nil)
        #expect(session.exercises.count == 2)

        let bench = session.exercises[0]
        #expect(bench.name == "Bench Press")
        #expect(bench.sets.count == 3)
        #expect(bench.sets.allSatisfy { $0.reps == 5 } == true)
        #expect(abs(bench.sets[0].weightKg - 100) <= 1e-6)

        let ohp = session.exercises[1]
        #expect(ohp.sets.map(\.reps) == [5, 5, 4])
    }

    @Test func poundsConvertToKg() {
        let result = GmailImporter.parse("Deadlift 225lb 5x1")
        let set = result.sessions[0].exercises[0].sets[0]
        #expect(abs(set.weightKg - WorkoutMath.lbToKg(225)) <= 1e-6)
    }

    @Test func pRMarkersAreStripped() {
        let result = GmailImporter.parse("Incline DB Press 30kg 8x3 PR")
        #expect(result.issues.isEmpty)
        let ex = result.sessions[0].exercises[0]
        #expect(ex.name == "Incline DB Press")
        #expect(ex.sets.count == 8)
        #expect(ex.sets[0].reps == 3)
    }

    @Test func multipleSessions() {
        let text = """
        # Push 2024-01-15
        Bench Press 100 3x5

        # Pull 2024-01-17
        Deadlift 180 5x1
        """
        let result = GmailImporter.parse(text)
        #expect(result.sessions.count == 2)
        #expect(result.sessions[1].title == "Pull")
    }

    @Test func unparseableLineFlaggedRestImported() {
        let text = """
        # Day
        Bench Press 100 3x5
        this line is gibberish
        Squat 140 5x3
        """
        let result = GmailImporter.parse(text)
        #expect(result.issues.count == 1)
        #expect(result.issues[0].text == "this line is gibberish")
        #expect(result.sessions[0].exercises.count == 2)
    }

    @Test func setsRepsParsing() {
        #expect(GmailImporter.parseSetsReps("3x5") == [5, 5, 5])
        #expect(GmailImporter.parseSetsReps("5x1") == [1, 1, 1, 1, 1])
        #expect(GmailImporter.parseSetsReps("5,5,4") == [5, 5, 4])
        #expect(GmailImporter.parseSetsReps("8") == [8])
        #expect(GmailImporter.parseSetsReps("abc") == nil)
        #expect(GmailImporter.parseSetsReps("3x") == nil)
    }

    @Test func weightParsing() {
        #expect(GmailImporter.parseWeight("100", defaultUnit: .kilograms) == 100)
        #expect(GmailImporter.parseWeight("100kg", defaultUnit: .pounds) == 100)
        #expect(abs(GmailImporter.parseWeight("225lb", defaultUnit: .kilograms)! - WorkoutMath.lbToKg(225)) <= 1e-6)
        #expect(GmailImporter.parseWeight("heavy", defaultUnit: .kilograms) == nil)
    }

    @Test func bareDateLineStartsSession() {
        let text = """
        2024-03-01
        Squat 140 5x5
        """
        let result = GmailImporter.parse(text)
        #expect(result.sessions.count == 1)
        #expect(result.sessions[0].date != nil)
        #expect(result.sessions[0].exercises.count == 1)
    }

    @Test func totalSetsCount() {
        let result = GmailImporter.parse("# D\nBench 100 3x5\nSquat 140 5x3")
        #expect(result.totalSets == 8)
    }
}
