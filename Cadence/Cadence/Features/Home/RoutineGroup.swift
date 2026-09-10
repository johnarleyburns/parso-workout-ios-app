import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

enum PlanningRoutineGroup {
    static let fiveByFive = StrengthPresets.all.filter { $0.id.hasPrefix("preset-5x5") }
    static let fiveThreeOne = StrengthPresets.all.filter { $0.id.hasPrefix("preset-531") }
    static let dup = StrengthPresets.all.filter { $0.id.hasPrefix("preset-dup") }
    static let linearPeriodization = StrengthPresets.all.filter { $0.id.hasPrefix("preset-lp") }
    static let clusterSets = StrengthPresets.all.filter { $0.id == "preset-cluster" }
    static let ppl = StrengthPresets.all.filter { $0.id.hasPrefix("preset-ppl") }
    static let splits = StrengthPresets.all.filter {
        ["preset-push", "preset-pull", "preset-legs", "preset-upper",
         "preset-lower", "preset-chest", "preset-back-bi"].contains($0.id)
    }
    static let calisthenics = StrengthPresets.all.filter { $0.id.hasPrefix("preset-cali") }
    static let olympic = StrengthPresets.all.filter { $0.id.hasPrefix("preset-oly") }
}
