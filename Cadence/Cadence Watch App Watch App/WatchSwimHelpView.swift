import SwiftUI

struct WatchSwimHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Water lock turns on after the swim starts. Press and hold the Digital Crown to unlock and eject water, then pause or end the swim.")
                    Text("Raise your wrist to see swim metrics. Unlock the watch before starting and wear the band snugly so the sensor stays against your skin.")
                    Text("If a passcode appears, watchOS has security-locked the watch. Cladiron cannot unlock it. Check band fit, Wake on Wrist Raise, and Settings → General → Return to Clock → Cladiron → Return to App during workouts.")
                    Link("Apple Watch wrist detection help", destination: URL(string: "https://support.apple.com/en-us/111819")!)
                }
                .font(.caption)
                .padding()
            }
            .navigationTitle("Swim help")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
