import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchCardioSetupView: View {
    let kind: WorkoutConfigurationSpec.CardioKind
    @Binding var location: WorkoutConfigurationSpec.Location
    @Binding var lapLength: Double
    let unit: MeasurementUnitPreference
    let onStart: (WorkoutConfigurationSpec) -> Void

    @Environment(\.dismiss) private var dismiss

    private var gpsOn: Bool {
        switch location {
        case .outdoor, .openWater: return true
        case .indoor, .pool: return false
        }
    }

    private func setGpsOn(_ on: Bool) {
        if on {
            location = kind == .swim ? .openWater : .outdoor
        } else {
            location = kind == .swim ? .pool(lapLength: 25) : .indoor
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(displayName).font(.headline)

            switch kind {
            case .run, .walk, .cycle, .swim, .rowing:
                HStack {
                    Text("GPS").font(.headline.weight(.semibold))
                    Spacer()
                    Toggle("", isOn: Binding(get: { gpsOn }, set: { setGpsOn($0) }))
                        .labelsHidden()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            default:
                EmptyView()
            }

            Button(buttonTitle) {
                let spec = WorkoutConfigurationSpec(kind: kind, location: resolvedLocation)
                onStart(spec)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
        .onAppear { normalizeLocationForKind() }
    }

    private var displayName: String {
        switch kind {
        case .run: return String(localized: "Run")
        case .walk: return String(localized: "Walk")
        case .cycle: return String(localized: "Cycle")
        case .swim: return String(localized: "Swim")
        case .rowing: return String(localized: "Rowing")
        case .other: return String(localized: "Other")
        default: return String(localized: "Setup")
        }
    }

    private var buttonTitle: String {
        switch kind {
        case .run: return String(localized: "Start run")
        case .walk: return String(localized: "Start walk")
        case .cycle: return String(localized: "Start cycle")
        case .swim: return String(localized: "Start swim")
        case .rowing: return String(localized: "Start row")
        case .other: return String(localized: "Start other")
        default: return String(localized: "Start")
        }
    }

    private var resolvedLocation: WorkoutConfigurationSpec.Location {
        switch kind {
        case .run, .walk, .cycle, .rowing:
            if gpsOn { return .outdoor } else { return .indoor }
        case .swim:
            if gpsOn { return .openWater } else { return .pool(lapLength: lapLength) }
        default:
            return .indoor
        }
    }

    private func normalizeLocationForKind() {
        switch kind {
        case .run, .walk, .cycle, .rowing:
            if case .pool = location { location = .outdoor }
            if case .openWater = location { location = .outdoor }
        case .swim:
            switch location {
            case .pool, .openWater:
                break
            case .indoor, .outdoor:
                location = .pool(lapLength: lapLength)
            }
        default:
            location = .indoor
        }
    }
}
