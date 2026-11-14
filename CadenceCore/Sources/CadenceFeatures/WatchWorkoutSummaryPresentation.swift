import Foundation
import CadenceCore

/// Single pure source of truth for the static content of a Watch workout summary, used by both the
/// immediate post-finish screens and read-only history. Completion-only controls live in `actions`.
public struct WatchWorkoutSummaryPresentation: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case receipt, retry, done, save, discard }
    public enum Omission: Equatable, Sendable { case heartRate, cardioCredit, exercises }

    public struct ExerciseDisplay: Equatable, Sendable {
        public let name: String
        /// e.g. "185 lb × 5"; warm-ups are prefixed, RPE appended when recorded.
        public let setTexts: [String]
    }

    public let id: UUID
    public let kind: WatchWorkoutHistorySummary.Kind
    public let title: String
    public let start: Date
    public let durationSeconds: TimeInterval
    public let isHistorical: Bool
    public let workingSetCount: Int?
    public let volumeText: String?
    public let distanceMeters: Double?
    public let laps: Int?
    public let hrSamples: [HRSamplePoint]
    public let averageBPM: Double?
    public let maximumBPM: Double?
    public let minutes: WatchCardioMinutesSummary?
    public let coverage: HeartRateCoveragePresentation?
    public let unclassifiedNote: String?
    public let exercises: [ExerciseDisplay]
    public let omissions: [Omission]

    public var showsHeartRateChart: Bool { !hrSamples.isEmpty }

    /// Transient controls/receipts. Always empty for historical presentations.
    public var actions: [Action] {
        guard !isHistorical else { return [] }
        return kind == .strength ? [.receipt, .retry, .done] : [.save, .discard]
    }

    public static func make(summary: WatchWorkoutHistorySummary, unit: MeasurementUnitPreference,
                            isHistorical: Bool) -> WatchWorkoutSummaryPresentation {
        let hasHR = !summary.hrSamples.isEmpty
        var omissions: [Omission] = []
        if !hasHR { omissions.append(.heartRate) }
        let minutes = WatchCardioMinutesSummary.make(summary: summary.minuteSummary)
        if hasHR && minutes == nil { omissions.append(.cardioCredit) }
        let exercises = summary.exercises.map { line in
            ExerciseDisplay(name: line.name, setTexts: line.sets.filter { $0.performerID == nil }.map { set in
                var text = "\(Format.weightValueQuarter(set.weightKg, unit: unit)) \(unit.abbreviation) × \(set.reps)"
                if let rpe = set.rpe { text += " @\(String(format: "%g", rpe))" }
                if set.isWarmup { text = String(localized: "Warm-up", bundle: .module) + " " + text }
                return text
            })
        }.filter { !$0.setTexts.isEmpty }
        if summary.kind == .strength && exercises.isEmpty { omissions.append(.exercises) }
        return WatchWorkoutSummaryPresentation(
            id: summary.id, kind: summary.kind, title: summary.title, start: summary.start,
            durationSeconds: summary.durationSeconds, isHistorical: isHistorical,
            workingSetCount: summary.workingSetCount,
            volumeText: summary.totalVolumeKg.map { "\(Format.weightValue($0, unit: unit, decimals: 0)) \(unit.abbreviation)" },
            distanceMeters: summary.distanceMeters, laps: summary.laps,
            hrSamples: summary.hrSamples, averageBPM: summary.averageBPM, maximumBPM: summary.maximumBPM,
            minutes: minutes,
            coverage: hasHR ? WatchStrengthHRCoverage.presentation(
                summary: summary.minuteSummary, sampleCount: summary.hrSamples.count, pending: false) : nil,
            unclassifiedNote: WatchStrengthHRCoverage.unclassifiedNote(summary: summary.minuteSummary),
            exercises: exercises, omissions: omissions)
    }
}

/// Where a My Workouts row opens.
public enum WatchMyWorkoutRoute: Equatable, Sendable {
    case plannedDetail
    case strengthSummary(UUID)
    /// Rich summary available (phone mirror or pending local completion).
    case cardioSummary(UUID)
    /// Legacy row without a rich snapshot: truthful basic fallback only.
    case cardioFallback(UUID)

    public static func route(for row: WatchMyWorkoutRow) -> WatchMyWorkoutRoute {
        switch row.source {
        case .planned: return .plannedDetail
        case .strength(let id): return .strengthSummary(id)
        case .cardio(let id): return row.hasRichSummary ? .cardioSummary(id) : .cardioFallback(id)
        }
    }
}
