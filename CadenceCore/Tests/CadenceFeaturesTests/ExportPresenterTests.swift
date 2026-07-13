import XCTest
import CadenceCore
import CadenceFeatures

final class ExportPresenterTests: XCTestCase {
    func testCardioBreakdownSortedByKey() {
        let expectedRun = CardioType(rawValue: "run")?.displayName ?? "Run"
        let expectedWalk = CardioType(rawValue: "walk")?.displayName ?? "Walk"
        let out = ExportPresenter.cardioBreakdown(["walk": 1, "run": 3])
        XCTAssertEqual(out, "\(expectedRun) 3 \u{00b7} \(expectedWalk) 1")
    }

    func testCardioBreakdownUnknownKeyCapitalized() {
        let out = ExportPresenter.cardioBreakdown(["zumba": 2])
        XCTAssertEqual(out, "Zumba 2")
    }

    func testDateSpanNilWithoutDates() {
        let s = ExportSummary()
        XCTAssertNil(ExportPresenter.dateSpan(s))
    }

    func testDateSpanSingleDay() {
        let d = Date(timeIntervalSince1970: 1_600_000_000)
        let s = ExportSummary(firstWorkoutDate: d, lastWorkoutDate: d, daysCovered: 1)
        let df = DateFormatter(); df.dateStyle = .medium
        XCTAssertEqual(ExportPresenter.dateSpan(s), df.string(from: d))
    }

    func testDateSpanRange() {
        let first = Date(timeIntervalSince1970: 1_600_000_000)
        let last = first.addingTimeInterval(33 * 86_400)
        let s = ExportSummary(firstWorkoutDate: first, lastWorkoutDate: last, daysCovered: 33)
        let span = ExportPresenter.dateSpan(s)
        XCTAssertTrue(span?.contains("33 days") == true)
        XCTAssertTrue(span?.contains("\u{2013}") == true)
    }

    func testSizeTextCSVUsesRaw() {
        let s = ExportSummary(rawByteCount: 2048, compressedByteCount: 0)
        let out = ExportPresenter.sizeText(s, isCSV: true)
        XCTAssertFalse(out.contains("raw"))
    }

    func testSizeTextJSONShowsCompressedAndRaw() {
        let s = ExportSummary(rawByteCount: 10_000, compressedByteCount: 2_000)
        let out = ExportPresenter.sizeText(s, isCSV: false)
        XCTAssertTrue(out.contains("raw"))
    }
}
