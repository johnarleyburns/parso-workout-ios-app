import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchCardioSetupView: View {
    let kind: WorkoutConfigurationSpec.CardioKind
    @Binding var location: WorkoutConfigurationSpec.Location
    @Binding var lapLength: Double
    let unit: MeasurementUnitPreference
    var plannedDurationSeconds: Int? = nil
    var targetZone: Int? = nil
    let onStart: (WorkoutConfigurationSpec) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var helpPresented = false

    private var gpsOn: Bool {
        switch location {
        case .outdoor, .openWater: return true
        case .indoor, .pool: return false
        }
    }

    private func setGpsOn(_ on: Bool) {
        location = on ? .outdoor : .indoor
    }

    var body: some View {
        ScrollView {
          VStack(spacing: 10) {
            Text(displayName).font(.headline)

            switch kind {
            case .swim:
                swimOptions
            case .run, .walk, .cycle, .rowing:
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
                let spec = WorkoutConfigurationSpec(kind: kind, location: resolvedLocation,
                                                      plannedDurationSeconds: plannedDurationSeconds,
                                                      targetZone: targetZone)
                onStart(spec)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
          }.padding()
        }
        .onAppear { normalizeLocationForKind() }
    }

    private var swimOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                swimModeButton("Lap Pool", mode: .lapPool)
                swimModeButton("Open Water w/GPS", mode: .openWater)
            }
            .accessibilityIdentifier("watch.swim.mode")
            if !gpsOn {
                Text("Pool length").font(.caption)
                HStack(spacing: 4) {
                    poolLengthButton(25)
                    poolLengthButton(50)
                }
                Text("Laps and distance track automatically. One lap is one pool length; updates can arrive shortly after a turn.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text("Water lock starts automatically. Hold the Digital Crown to unlock.")
                .font(.caption2).foregroundStyle(.secondary)
            Button("Water lock & screen help") { helpPresented = true }
                .font(.caption)
                .sheet(isPresented: $helpPresented) { WatchSwimHelpView() }
        }
    }

    private func swimModeButton(_ label: LocalizedStringKey, mode: WatchSwimMode) -> some View {
        let selected = (gpsOn ? WatchSwimMode.openWater : .lapPool) == mode
        return Button {
            location = WatchSwimSetup.configuration(mode: mode, poolLength: lapLength).location
        } label: {
            Text(label).font(.caption2.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color.green.opacity(0.25) : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func poolLengthButton(_ meters: Double) -> some View {
        Button {
            lapLength = meters
            location = .pool(lapLength: meters)
        } label: {
            Text("\(Int(meters)) m").font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(lapLength == meters ? Color.green.opacity(0.25) : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(Int(meters)) meter pool"))
        .accessibilityAddTraits(lapLength == meters ? .isSelected : [])
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
            return WatchSwimSetup.configuration(mode: gpsOn ? .openWater : .lapPool,
                                               poolLength: lapLength).location
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
            lapLength = lapLength == 50 ? 50 : 25
            switch location {
            case .pool:
                location = .pool(lapLength: lapLength)
            case .openWater:
                break
            case .indoor, .outdoor:
                location = .pool(lapLength: lapLength)
            }
        default:
            location = .indoor
        }
    }
}
