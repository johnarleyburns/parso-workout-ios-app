import SwiftUI

/// Root launcher for the Cladiron Watch App. Presents a glanceable list of
/// workout options so the user can start a session without the phone.
///
/// Phase 0 — foundation scaffolding. Taps navigate to placeholder views;
/// real interval/strength/partner flows ship in Phases 2–5.
struct WatchRootView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { StrengthPlaceholderView() }
                        label: { Label("Start Lift", systemImage: "dumbbell.fill") }

                    NavigationLink { IntervalPlaceholderView(kind: "HIIT") }
                        label: { Label("HIIT", systemImage: "flame.fill") }

                    NavigationLink { IntervalPlaceholderView(kind: "Boxing") }
                        label: { Label("Boxing", systemImage: "figure.boxing") }

                    NavigationLink { ResumePlaceholderView() }
                        label: { Label("Resume", systemImage: "arrow.counterclockwise") }
                }

                Section {
                    NavigationLink { HRSettingsPlaceholderView() }
                        label: { Label("Settings", systemImage: "gearshape.fill") }
                }
            }
            .navigationTitle("Cladiron")
        }
    }
}

// MARK: - Placeholder views (replaced in later phases)

private struct StrengthPlaceholderView: View {
    var body: some View {
        Text("Strength logging ships in Phase 3")
            .foregroundStyle(.secondary)
            .navigationTitle("Lift")
    }
}

private struct IntervalPlaceholderView: View {
    let kind: String
    var body: some View {
        Text("\(kind) timer ships in Phase 2")
            .foregroundStyle(.secondary)
            .navigationTitle(kind)
    }
}

private struct ResumePlaceholderView: View {
    var body: some View {
        Text("Resume ships in Phase 3")
            .foregroundStyle(.secondary)
            .navigationTitle("Resume")
    }
}

private struct HRSettingsPlaceholderView: View {
    var body: some View {
        Text("HR settings ship in Phase 1")
            .foregroundStyle(.secondary)
            .navigationTitle("Settings")
    }
}

#Preview {
    WatchRootView()
        .environment(WatchWorkoutManager())
}
