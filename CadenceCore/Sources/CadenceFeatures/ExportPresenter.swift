import Foundation
import CadenceCore

/// Pure formatting for the Export screen's summary card (test-pyramid Phase 1):
/// the cardio breakdown line, the date-range span, and the backup-size string.
/// Moved out of `ExportView`; the actual `CadenceExport` build/encode is already
/// covered by `DataExport`/`ExportSummary` tests in CadenceCore.
public enum ExportPresenter {

    /// "Run 3 · Walk 1", sorted by raw type key, mapping known types to display names.
    public static func cardioBreakdown(_ byType: [String: Int]) -> String {
        byType.sorted { $0.key < $1.key }
            .map { key, count in
                let name = CardioType(rawValue: key)?.displayName ?? key.capitalized
                return "\(name) \(count)"
            }
            .joined(separator: " \u{00b7} ")
    }

    /// "Jan 1 – Feb 3 · 33 days", or a single date when the span is ≤1 day; nil
    /// when the summary has no workout dates.
    public static func dateSpan(_ s: ExportSummary,
                                dateStyle: DateFormatter.Style = .medium) -> String? {
        guard let first = s.firstWorkoutDate, let last = s.lastWorkoutDate else { return nil }
        let df = DateFormatter(); df.dateStyle = dateStyle
        if s.daysCovered <= 1 { return df.string(from: first) }
        return "\(df.string(from: first)) \u{2013} \(df.string(from: last)) \u{00b7} \(s.daysCovered) days"
    }

    /// Backup size string: raw bytes for CSV/uncompressed, else "compressed (raw)".
    public static func sizeText(_ s: ExportSummary, isCSV: Bool) -> String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        if isCSV || s.compressedByteCount == 0 {
            return fmt.string(fromByteCount: Int64(s.rawByteCount))
        }
        return "\(fmt.string(fromByteCount: Int64(s.compressedByteCount))) (\(fmt.string(fromByteCount: Int64(s.rawByteCount))) raw)"
    }
}
