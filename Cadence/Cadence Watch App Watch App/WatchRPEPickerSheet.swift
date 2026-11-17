import SwiftUI
import CadenceCore
import CadenceFeatures

/// RPE choices presented from More; `onSelect(nil)` clears the rating.
struct WatchRPEPickerSheet: View {
    let onSelect: (Int?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button("None") { onSelect(nil) }.accessibilityIdentifier("watchEffort.none")
                ForEach(WatchRPESelection.options, id: \.self) { value in
                    Button("RPE \(value)") { onSelect(value) }
                        .accessibilityIdentifier("watchEffort.\(value)")
                }
            }
            .navigationTitle("RPE")
        }
    }
}
