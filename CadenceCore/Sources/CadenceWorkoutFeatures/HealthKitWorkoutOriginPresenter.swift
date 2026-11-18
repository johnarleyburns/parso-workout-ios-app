import CadenceFeatures
import Foundation
import CadenceCore

/// User-facing provenance for an imported HealthKit workout.
public struct HealthKitWorkoutOriginLabel: Equatable, Sendable {
    /// e.g. "Imported from Strava". Always present.
    public let primary: String
    /// Source app / device detail for the detail screen; nil when unknown.
    public let detail: String?
    public let accessibilityLabel: String
}

/// Pure presenter. Precedence: Fitness+, workout brand, source + distinct
/// device, source, device, generic. Bundle identifiers are never displayed.
public enum HealthKitWorkoutOriginPresenter {
    public static func label(for provenance: HealthKitWorkoutProvenance?) -> HealthKitWorkoutOriginLabel {
        guard let p = provenance else { return make({
            #if os(Linux)
            "Imported from HealthKit"
            #else
            String(localized: "Imported from HealthKit")
            #endif
        }(), nil) }
        let source = clean(p.sourceName)
        let device = clean(p.deviceName) ?? clean(p.deviceModel)
        let detail = detailText(source: source, device: device)

        if p.isAppleFitnessPlus {
            return make({
                #if os(Linux)
                "Imported from Apple Fitness+"
                #else
                String(localized: "Imported from Apple Fitness+")
                #endif
            }(), detail)
        }
        if let brand = clean(p.workoutBrandName) {
            return make({
                #if os(Linux)
                "Imported from \(brand)"
                #else
                String(localized: "Imported from \(brand)")
                #endif
            }(), detail)
        }
        if let source, let device, !same(source, device) {
            return make({
                #if os(Linux)
                "Imported from \(source) on \(device)"
                #else
                String(localized: "Imported from \(source) on \(device)")
                #endif
            }(), detail)
        }
        if let source { return make({
            #if os(Linux)
            "Imported from \(source)"
            #else
            String(localized: "Imported from \(source)")
            #endif
        }(), detail) }
        if let device { return make({
            #if os(Linux)
            "Imported from \(device)"
            #else
            String(localized: "Imported from \(device)")
            #endif
        }(), detail) }
        return make({
            #if os(Linux)
            "Imported from HealthKit"
            #else
            String(localized: "Imported from HealthKit")
            #endif
        }(), nil)
    }

    private static func detailText(source: String?, device: String?) -> String? {
        switch (source, device) {
        case let (s?, d?) where !same(s, d): return {
            #if os(Linux)
            "\(s) on \(d)"
            #else
            String(localized: "\(s) on \(d)")
            #endif
        }()
        case let (s?, _): return s
        case let (nil, d?): return d
        default: return nil
        }
    }

    private static func make(_ primary: String, _ detail: String?) -> HealthKitWorkoutOriginLabel {
        let a11y = detail.map { d in
            #if os(Linux)
            "\(primary). Recorded by \(d)"
            #else
            String(localized: "\(primary). Recorded by \(d)")
            #endif
        } ?? primary
        return HealthKitWorkoutOriginLabel(primary: primary, detail: detail, accessibilityLabel: a11y)
    }

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
