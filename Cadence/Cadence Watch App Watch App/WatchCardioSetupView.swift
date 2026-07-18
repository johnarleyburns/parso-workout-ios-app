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

    var body: some View {
        VStack(spacing: 10) {
            Text(displayName).font(.headline)

            switch kind {
            case .run, .walk, .cycle:
                HStack(spacing: 0) {
                    Button("Outdoor") { location = .outdoor }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(location == .outdoor ? .white.opacity(0.22) : .white.opacity(0.08))
                        .foregroundStyle(location == .outdoor ? .white : .secondary)
                    Button("Indoor") { location = .indoor }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(location == .indoor ? .white.opacity(0.22) : .white.opacity(0.08))
                        .foregroundStyle(location == .indoor ? .white : .secondary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                if case .outdoor = location {
                    Text("GPS + pedometer distance.\nAuto-pauses when you stop.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            case .swim:
                HStack(spacing: 0) {
                    Button("Pool") { location = .pool(lapLength: lapLength) }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background({ if case .pool = location { true } else { false } }() ? .white.opacity(0.22) : .white.opacity(0.08))
                        .foregroundStyle({ if case .pool = location { true } else { false } }() ? .white : .secondary)
                    Button("Open water") { location = .openWater }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(location == .openWater ? .white.opacity(0.22) : .white.opacity(0.08))
                        .foregroundStyle(location == .openWater ? .white : .secondary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                if case .pool = location {
                    HStack(spacing: 8) {
                        Text("25 \(unit.abbreviation == "kg" ? "m" : "yd")").font(.caption.bold())
                            .padding(8).background(lapLength == 25 ? .blue : .white.opacity(0.1))
                            .clipShape(Capsule()).onTapGesture {
                                lapLength = 25
                                location = .pool(lapLength: 25)
                            }
                        Text("50 \(unit.abbreviation == "kg" ? "m" : "yd")").font(.caption.bold())
                            .padding(8).background(lapLength == 50 ? .blue : .white.opacity(0.1))
                            .clipShape(Capsule()).onTapGesture {
                                lapLength = 50
                                location = .pool(lapLength: 50)
                            }
                    }
                    Text("Laps count automatically.\nWater Lock turns on at start.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
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
        case .run: return "Run"
        case .walk: return "Walk"
        case .cycle: return "Cycle"
        case .swim: return "Swim"
        case .rowing: return "Rowing"
        case .other: return "Other"
        default: return "Setup"
        }
    }

    private var buttonTitle: String {
        switch kind {
        case .run: return "Start run"
        case .walk: return "Start walk"
        case .cycle: return "Start cycle"
        case .swim: return "Start swim"
        case .rowing: return "Start row"
        case .other: return "Start other"
        default: return "Start"
        }
    }

    private var resolvedLocation: WorkoutConfigurationSpec.Location {
        switch kind {
        case .run, .walk, .cycle:
            switch location {
            case .indoor, .outdoor:
                return location
            case .pool, .openWater:
                return .outdoor
            }
        case .swim:
            switch location {
            case .pool:
                return .pool(lapLength: lapLength)
            case .openWater:
                return .openWater
            case .indoor, .outdoor:
                return .pool(lapLength: lapLength)
            }
        default:
            return .indoor
        }
    }

    private func normalizeLocationForKind() {
        switch kind {
        case .run, .walk, .cycle:
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
