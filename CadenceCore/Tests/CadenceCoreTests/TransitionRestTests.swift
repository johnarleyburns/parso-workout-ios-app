import Foundation
import Testing
@testable import CadenceCore

@Suite struct TransitionRestTests {
    private func item(default d: Int?, transition t: Int?) -> StrengthItem {
        StrengthItem(exerciseKey: ExerciseKey(raw: "squat"), order: 0,
                     defaultRestSeconds: d,
                     sets: (0..<3).map { PrescribedSet(setIndex: $0, repTarget: .exact(5)) },
                     schemeApplied: nil, supersetGroup: nil, laterality: nil,
                     progression: nil, performerOverrides: nil,
                     transitionRestSeconds: t)
    }

    @Test func eachRestTypeChangesOnlyItsOwnTiming() {
        let base = item(default: 90, transition: 180)
        #expect(base.totalBetweenSetRestSeconds == 180)
        #expect(base.effectiveTransitionRestSeconds == 180)
        let longerTransition = item(default: 90, transition: 300)
        #expect(longerTransition.totalBetweenSetRestSeconds == 180)
        #expect(longerTransition.effectiveTransitionRestSeconds == 300)
        let longerSets = item(default: 120, transition: 180)
        #expect(longerSets.totalBetweenSetRestSeconds == 240)
        #expect(longerSets.effectiveTransitionRestSeconds == 180)
    }

    @Test func legacyDataDecodesAndFallsBack() throws {
        let legacy = item(default: 90, transition: nil)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        json.removeValue(forKey: "transitionRestSeconds")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(StrengthItem.self, from: data)
        #expect(decoded.transitionRestSeconds == nil)
        #expect(decoded.effectiveTransitionRestSeconds == 90)
        #expect(decoded.totalBetweenSetRestSeconds == 180)
    }

    @Test func roundTripAndValidation() throws {
        let value = item(default: 60, transition: 150)
        let back = try JSONDecoder().decode(StrengthItem.self, from: JSONEncoder().encode(value))
        #expect(back == value)
        try value.validate()
        var bad = value
        bad.transitionRestSeconds = -1
        #expect(throws: UnifiedPlanValidationError.invalidRest) { try bad.validate() }
    }
}
