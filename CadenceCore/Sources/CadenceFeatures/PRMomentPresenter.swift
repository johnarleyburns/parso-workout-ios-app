import Foundation
import CadenceCore

public struct PRMoment: Equatable, Sendable {
    public let headline: String
    public let context: String
    public let performerName: String?
    public init(headline: String, context: String, performerName: String? = nil) {
        self.headline = headline; self.context = context; self.performerName = performerName
    }
}

/// Complete payload for the in-session PR takeover. It keeps the new value,
/// previous best, improvement, and governing rule together for phone/watch UI.
public struct PRTakeover: Equatable, Sendable {
    public let headline: String
    public let exerciseName: String
    public let newValue: String
    public let previousValue: String?
    public let improvement: String?
    public let ruleLabel: String

    public init(headline: String, exerciseName: String, newValue: String,
                previousValue: String?, improvement: String?, ruleLabel: String) {
        self.headline = headline; self.exerciseName = exerciseName
        self.newValue = newValue; self.previousValue = previousValue
        self.improvement = improvement; self.ruleLabel = ruleLabel
    }
}

public enum PRMomentPresenter {
    public static func takeover(for event: PREvent, unit: MeasurementUnitPreference,
                                performerName: String? = nil) -> PRTakeover {
        let headline = performerName.map { "\($0)'s new personal record" } ?? "New personal record"
        let previous = event.previous.map { valueLabel($0, kind: event.kind, unit: unit) }
        let improvement = event.previous.map {
            deltaLabel(event.value - $0, kind: event.kind, unit: unit)
        }
        let ruleLabel: String
        switch event.kind {
        case .weight: ruleLabel = "Heaviest weight"
        case .e1RM: ruleLabel = "Estimated one-rep max"
        case .volume: ruleLabel = "Single-set volume"
        }
        return PRTakeover(headline: headline, exerciseName: event.exerciseName,
                          newValue: valueLabel(event.value, kind: event.kind, unit: unit),
                          previousValue: previous, improvement: improvement,
                          ruleLabel: ruleLabel)
    }

    public static func moment(exercise: String, loadText: String, changeText: String,
                              isNewPR: Bool, isWarmup: Bool, isPartnerSet: Bool,
                              performerName: String? = nil) -> PRMoment? {
        guard isNewPR, !isWarmup else { return nil }
        let headline = isPartnerSet ? "\(performerName ?? "Partner")'s new personal record" : "New personal record"
        return PRMoment(headline: headline, context: "\(exercise) \(loadText) · \(changeText)",
                        performerName: performerName)
    }

    private static func valueLabel(_ value: Double, kind: PRKind,
                                   unit: MeasurementUnitPreference) -> String {
        switch kind {
        case .weight: return Format.weight(value, unit: unit, decimals: 0)
        case .e1RM: return "\(Format.weight(value, unit: unit, decimals: 0)) e1RM"
        case .volume:
            return "\(Int(WorkoutMath.display(value, in: unit).rounded())) \(unit.abbreviation)·reps"
        }
    }

    private static func deltaLabel(_ value: Double, kind: PRKind,
                                   unit: MeasurementUnitPreference) -> String {
        switch kind {
        case .weight, .e1RM:
            return "+\(Format.weight(value, unit: unit, decimals: 0)) over previous"
        case .volume:
            return "+\(Int(WorkoutMath.display(value, in: unit).rounded())) \(unit.abbreviation)·reps over previous"
        }
    }
}
