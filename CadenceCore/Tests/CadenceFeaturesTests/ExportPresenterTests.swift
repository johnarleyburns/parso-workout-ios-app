import Foundation
import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct ExportPresenterTests {
    @Test func cardioBreakdownSortedByKey() {
        let expectedRun = CardioType(rawValue: "run")?.displayName ?? "Run"
        let expectedWalk = CardioType(rawValue: "walk")?.displayName ?? "Walk"
        let out = ExportPresenter.cardioBreakdown(["walk": 1, "run": 3])
        #expect(out == "\(expectedRun) 3 \u{00b7} \(expectedWalk) 1")
    }

    @Test func cardioBreakdownUnknownKeyCapitalized() {
        let out = ExportPresenter.cardioBreakdown(["zumba": 2])
        #expect(out == "Zumba 2")
    }

    @Test func dateSpanNilWithoutDates() {
        let s = ExportSummary()
        #expect(ExportPresenter.dateSpan(s) == nil)
    }

    @Test func dateSpanSingleDay() {
        let d = Date(timeIntervalSince1970: 1_600_000_000)
        let s = ExportSummary(firstWorkoutDate: d, lastWorkoutDate: d, daysCovered: 1)
        let df = DateFormatter(); df.dateStyle = .medium
        #expect(ExportPresenter.dateSpan(s) == df.string(from: d))
    }

    @Test func dateSpanRange() {
        let first = Date(timeIntervalSince1970: 1_600_000_000)
        let last = first.addingTimeInterval(33 * 86_400)
        let s = ExportSummary(firstWorkoutDate: first, lastWorkoutDate: last, daysCovered: 33)
        let span = ExportPresenter.dateSpan(s)
        #expect(span?.contains("33 days") == true)
        #expect(span?.contains("\u{2013}") == true)
    }

    @Test func sizeTextCSVUsesRaw() {
        let s = ExportSummary(rawByteCount: 2048, compressedByteCount: 0)
        let out = ExportPresenter.sizeText(s, isCSV: true)
        #expect(!out.contains("raw"))
    }

    @Test func sizeTextJSONShowsCompressedAndRaw() {
        let s = ExportSummary(rawByteCount: 10_000, compressedByteCount: 2_000)
        let out = ExportPresenter.sizeText(s, isCSV: false)
        #expect(out.contains("raw"))
    }
}
