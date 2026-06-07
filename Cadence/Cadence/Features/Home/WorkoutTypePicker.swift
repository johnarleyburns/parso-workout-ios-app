import SwiftUI
import CadenceCore

/// The Start Workout type chooser (field-testing §02, decision #9). One fast
/// decision: pick a type, route to its purpose-built screen. Large, legible
/// cards for at-a-glance / low-vision use.
struct WorkoutTypePicker: View {
    let onSelect: (WorkoutType) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 16),
                           GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(WorkoutType.allCases) { type in
                        Button {
                            onSelect(type)
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: type.symbol).font(.system(size: 34))
                                Text(type.displayName).font(.headline)
                                if type.usesGPS {
                                    Text("GPS").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .padding(.vertical, 12)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("startType.\(type.rawValue)")
                        .accessibilityLabel(type.displayName)
                    }
                }
                .padding()
            }
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("startType.cancel")
                }
            }
        }
    }
}
