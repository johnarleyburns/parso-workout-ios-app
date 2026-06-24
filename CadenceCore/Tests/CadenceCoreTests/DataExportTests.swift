import XCTest
@testable import CadenceCore

final class DataExportTests: XCTestCase {

    private func sampleExport() -> CadenceExport {
        let setID = UUID(); let sessID = UUID()
        let set = ExportSet(id: setID, exerciseName: "Bench Press", category: "push",
                            weightKg: 100, reps: 5, order: 0, isWarmup: false,
                            rpe: 8, note: "felt strong", completedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let session = ExportSession(id: sessID, title: "Push Day",
                                    date: Date(timeIntervalSince1970: 1_700_000_000),
                                    notes: nil, sets: [set])
        return CadenceExport(exportedAt: Date(timeIntervalSince1970: 1_700_000_100), sessions: [session])
    }

    func testJSONRoundTrip() throws {
        let original = sampleExport()
        let data = try DataExport.encodeJSON(original)
        let decoded = try DataExport.decodeJSON(data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.version, CadenceExport.currentVersion)
    }

    func testCSVHasHeaderAndRow() {
        let csv = DataExport.encodeCSV(sampleExport())
        let lines = csv.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].hasPrefix("session_id,session_title"))
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("Bench Press"))
        XCTAssertTrue(lines[1].contains("100.0"))
    }

    func testCSVEscapesCommasAndQuotes() {
        XCTAssertEqual(DataExport.csvEscape("a,b"), "\"a,b\"")
        XCTAssertEqual(DataExport.csvEscape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(DataExport.csvEscape("plain"), "plain")
    }

    func testCSVQuotesNoteWithComma() {
        let setID = UUID()
        let set = ExportSet(id: setID, exerciseName: "Row", category: nil, weightKg: 60, reps: 8,
                            order: 0, isWarmup: false, rpe: nil, note: "back, then biceps",
                            completedAt: Date(timeIntervalSince1970: 0))
        let session = ExportSession(id: UUID(), title: "Pull", date: Date(timeIntervalSince1970: 0), notes: nil, sets: [set])
        let csv = DataExport.encodeCSV(CadenceExport(sessions: [session]))
        XCTAssertTrue(csv.contains("\"back, then biceps\""))
    }

    func testJSONExportIncludesCoachPreferences() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var profile = CoachPreferenceProfile.empty
        let session = CoachSession(
            id: "aerobic.moderateCycle", kind: .moderateAerobic,
            title: "Steady cycle", durationMinutes: 35,
            modality: .cycle, intensity: .moderate,
            launchPayload: .cardio(type: "cycle", durationMinutes: 35)
        )
        profile.recordSelection(session, from: [], at: now)

        let export = CadenceExport(
            sessions: [], cardio: [],
            coachPreferences: profile.exportDTO
        )

        let data = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(data)
        XCTAssertNotNil(decoded.coachPreferences)
        XCTAssertEqual(decoded.coachPreferences?.aerobicPreferences.count, 1)
        XCTAssertEqual(decoded.coachPreferences?.aerobicPreferences.first?.modality, "cycle")
        XCTAssertEqual(decoded.coachPreferences?.aerobicPreferences.first?.intent, "moderateAerobic")
    }

    func testJSONExportDecodesWhenCoachPreferencesMissing() throws {
        let json = """
        {"version":1,"exportedAt":"2025-06-01T00:00:00Z","sessions":[],"cardio":[]}
        """.data(using: .utf8)!
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertNil(decoded.coachPreferences, "Older exports without coachPreferences should decode with nil")
    }

    func testCoachPreferenceExportRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .cycle, score: 3, updatedAt: now)
        ]
        let dto = profile.exportDTO
        let export = CadenceExport(sessions: [], cardio: [], coachPreferences: dto)
        let data = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(data)
        XCTAssertEqual(decoded.coachPreferences?.profileVersion, 1)
        XCTAssertEqual(decoded.coachPreferences?.aerobicPreferences.first?.score, 3)
    }
}
