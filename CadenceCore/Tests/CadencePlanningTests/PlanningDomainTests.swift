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

    @Test func policyPresetsKeepShippedValues() {
        #expect(PlanningPolicy.safe.maxTotalSetsPerSession == 18)
        #expect(PlanningPolicy.safe.respectsRestDays)
        #expect(PlanningPolicy.meetDeficits.maxExtraStrengthSlots == 7)
        #expect(!PlanningPolicy.meetDeficits.respectsMRVCeiling)
    }
}
