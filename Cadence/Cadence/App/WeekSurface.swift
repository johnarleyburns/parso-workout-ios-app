import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// Strength and Cardio are no longer tab-bar items. The Home overflow menu asks
/// this presenter to open the week surface, and RootTabView shows it as a sheet.
enum WeekSurface: String, Identifiable {
    case strength, cardio

    var id: String { rawValue }
    var title: String {
        switch self {
        case .strength: return String(localized: "Strength")
        case .cardio: return String(localized: "Cardio")
        }
    }
}

@MainActor
@Observable
final class WeekSurfacePresenter {
    var surface: WeekSurface?

    func open(_ surface: WeekSurface) {
        self.surface = surface
    }
}

struct WeekSurfaceView: View {
    let surface: WeekSurface
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch surface {
                case .strength: StrengthView()
                case .cardio: CardioWeekView()
                }
            }
            .navigationTitle(surface.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("weekSurface.done")
                }
            }
        }
    }
}
