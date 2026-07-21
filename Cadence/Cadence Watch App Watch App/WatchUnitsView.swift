import SwiftUI
import WatchConnectivity
import CadenceCore
import CadenceFeatures

struct WatchUnitsView: View {
    @Environment(\.dismiss) private var dismiss
    let appSettings: AppSettings

    var body: some View {
        List {
            Section("Weight") {
                ForEach(MeasurementUnitPreference.allCases) { unit in
                    Button {
                        appSettings.unit = unit
                        sendSetUnit(unit)
                        dismiss()
                    } label: {
                        HStack {
                            Text(unit.displayName)
                            Spacer()
                            if appSettings.unit == unit {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("Distance") {
                ForEach(DistanceUnitPreference.allCases) { du in
                    Button {
                        appSettings.distanceUnit = du
                        sendSetDistanceUnit(du)
                        dismiss()
                    } label: {
                        HStack {
                            Text(du.displayName)
                            Spacer()
                            if appSettings.distanceUnit == du {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Units")
    }

    private func sendSetUnit(_ unit: MeasurementUnitPreference) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([
            "action": "set_unit",
            "value": unit.rawValue,
        ])
    }

    private func sendSetDistanceUnit(_ unit: DistanceUnitPreference) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([
            "action": "set_distance_unit",
            "value": unit.rawValue,
        ])
    }
}
