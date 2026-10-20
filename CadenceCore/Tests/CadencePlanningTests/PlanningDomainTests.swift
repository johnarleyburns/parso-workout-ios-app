import Foundation
import Testing
@testable import CadencePlanning

struct PlanningDomainTests {
    private static let prohibited = ["SwiftUI", "SwiftData", "HealthKit", "UIKit",
                                     "WatchConnectivity", "CoreLocation", "StoreKit",
                                     "CadenceCore", "CadenceFeatures"]

    @Test func sourcesImportOnlyFoundation() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CadencePlanning")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            for line in text.split(separator: "\n") where line.trimmingCharacters(in: .whitespaces).hasPrefix("import ") {
                let module = line.trimmingCharacters(in: .whitespaces).dropFirst(7)
                    .trimmingCharacters(in: .whitespaces)
                #expect(module == "Foundation", "\(file) imports \(module)")
                #expect(!Self.prohibited.contains(module))
            }
        }
    }

    @Test func planningIsDeterministic() throws {
        let input = try PlanningInput(strengthDaysPerWeek: 3, cardioDaysPerWeek: 2,
                                      restRule: .rolling(everyNDays: 3))
        let a = try WeekSlotPlanner.plan(input, weekStartWeekday: 2)
        let b = try WeekSlotPlanner.plan(input, weekStartWeekday: 2)
        #expect(a == b)
        #expect(a.strengthCount == 3)
        #expect(a.cardioCount == 2)
        #expect(a.slots.count == 7)
    }

    @Test func fixedRestDaysAreNeverTrained() throws {
        let input = try PlanningInput(strengthDaysPerWeek: 4, cardioDaysPerWeek: 3,
                                      restRule: .fixed(weekdays: [1, 7]))
        let out = try WeekSlotPlanner.plan(input, weekStartWeekday: 1)
        for slot in out.slots where [1, 7].contains(slot.weekday) {
            #expect(slot.kinds == [.rest])
        }
    }

    @Test func validationRejectsBadInput() {
        #expect(throws: PlanningInputError.strengthDaysOutOfRange(1)) {
            try PlanningInput(strengthDaysPerWeek: 1, cardioDaysPerWeek: 0, restRule: .rolling(everyNDays: 3))
        }
        #expect(throws: PlanningInputError.cardioDaysOutOfRange(8)) {
            try PlanningInput(strengthDaysPerWeek: 2, cardioDaysPerWeek: 8, restRule: .rolling(everyNDays: 3))
        }
        #expect(throws: PlanningInputError.invalidRollingRest(0)) {
            try PlanningInput(strengthDaysPerWeek: 2, cardioDaysPerWeek: 0, restRule: .rolling(everyNDays: 0))
        }
        #expect(throws: PlanningInputError.invalidWeekday(9)) {
            try PlanningInput(strengthDaysPerWeek: 2, cardioDaysPerWeek: 0, restRule: .fixed(weekdays: [9]))
        }
        #expect(throws: PlanningInputError.invalidWeekday(0)) {
            let input = try PlanningInput(strengthDaysPerWeek: 2, cardioDaysPerWeek: 0, restRule: .rolling(everyNDays: 3))
            _ = try WeekSlotPlanner.plan(input, weekStartWeekday: 0)
        }
    }

    @Test func policyPresetsKeepShippedValues() {
        #expect(PlanningPolicy.safe.maxTotalSetsPerSession == 18)
        #expect(PlanningPolicy.safe.respectsRestDays)
        #expect(PlanningPolicy.meetDeficits.maxExtraStrengthSlots == 7)
        #expect(!PlanningPolicy.meetDeficits.respectsMRVCeiling)
    }
}
