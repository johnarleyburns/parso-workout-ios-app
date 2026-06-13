import SwiftUI
import CadenceCore

/// The CrossFit entry point (round4b §B-1). Lists the benchmark "Girls" workouts;
/// tapping one shows a prescription preview, and Start launches a planned session
/// pre-loaded with the movements + Rx (logged in the normal strength flow).
///
/// Pushed inside the Start-Workout sheet's navigation (P1 #1) so moving here from
/// the type chooser is a push, not a sheet-swap that flashes Home. Launching is
/// the parent's job (`onStart`), which dismisses the whole sheet at once.
struct CrossFitPickerView: View {
    /// Called with the chosen plan once the user taps Start.
    let onStart: (WorkoutPlan) -> Void

    /// Benchmarks listed alphabetically (P1 #2).
    private var benchmarks: [WorkoutPlan] {
        BenchmarkWorkouts.girls.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section("Benchmark workouts") {
                ForEach(benchmarks) { plan in
                    NavigationLink {
                        CrossFitPreviewView(plan: plan) { onStart(plan) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.name).font(.headline)
                            Text(plan.schemeSummary)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("crossfit.row.\(plan.id)")
                }
            }
            Section {
                Link(destination: URL(string: "https://www.crossfit.com/crossfit-movements")!) {
                    Label("CrossFit movement guide", systemImage: "arrow.up.right.square")
                }
                .accessibilityIdentifier("crossfit.movementGuide")
            }
        }
        .navigationTitle("CrossFit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A read-only prescription preview for one benchmark, with a big Start button.
struct CrossFitPreviewView: View {
    let plan: WorkoutPlan
    /// A chosen per-set rep ladder for a flexible strength template (feedback
    /// batch 3) — applied to every movement in the preview + the launched session.
    var repLadder: [Int]? = nil
    let onStart: () -> Void
    @Environment(AppSettings.self) private var settings

    /// Rep-ladder schemes apply the ladder to every item; a chosen template
    /// ladder takes precedence, then a benchmark's `forTime` rounds.
    private var ladder: [Int]? {
        if let repLadder, !repLadder.isEmpty { return repLadder }
        if case let .forTime(rounds, _) = plan.scheme { return rounds }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(plan.schemeSummary)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("crossfit.preview.scheme")

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.items) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.movement).font(.headline)
                            let line = Format.prescription(item, ladder: ladder, unit: settings.unit)
                            if !line.isEmpty {
                                Text(line).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

                if let notes = plan.notes {
                    Text(notes).font(.footnote).foregroundStyle(.secondary)
                }

                Button(action: onStart) {
                    Label("Start", systemImage: "play.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("crossfit.preview.start")
            }
            .padding()
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
