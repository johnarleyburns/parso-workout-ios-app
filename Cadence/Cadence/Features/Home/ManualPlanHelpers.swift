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
    case .walk: return "Walk"
    case .run: return "Run"
    case .bike: return "Bike"
    case .row: return "Row"
    case .swim: return "Swim"
    case .elliptical: return "Elliptical"
    case .stairs: return "Stairs"
    case let .other(value): return value
    }
}
