import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

func manualIntensityText(for intensity: CardioIntensity?) -> String {
    switch intensity {
    case let .heartRateZone(zone): return String(zone)
    case let .rpe(range): return String(range.lowerBound)
    default: return ""
    }
}

func manualIntensityMode(for intensity: CardioIntensity?) -> ManualIntensityMode {
    switch intensity {
    case .talkTest: return .talkTest
    case .rpe: return .rpe
    default: return .heartRateZone
    }
}

func manualIntensityValue(for intensity: CardioIntensity?) -> String {
    manualIntensityText(for: intensity)
}

func cardioActivityName(_ activity: CardioActivity) -> String {
    switch activity {
    case .walk: return String(localized: "Walk")
    case .run: return String(localized: "Run")
    case .bike: return String(localized: "Bike")
    case .row: return "Row"
    case .swim: return String(localized: "Swim")
    case .elliptical: return String(localized: "Elliptical")
    case .stairs: return String(localized: "Stairs")
    case let .other(value): return value
    }
}
