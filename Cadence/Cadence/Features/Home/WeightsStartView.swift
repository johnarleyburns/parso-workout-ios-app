import SwiftUI
import SwiftData
import CadenceCore

/// The Weights entry point (round4b feedback #1). Three ways to begin a strength
/// session: **Quick Start** (a blank workout), **Start from Previous Workout**
/// (one of your recent non-CrossFit sessions, reused as a template), or **Start
/// from Library** (a built-in split — 5×5, Push/Pull/Legs, body-part days,
/// Olympic). Pushed inside the Start-Workout sheet (like CrossFit), so launching
/// is the parent's job and dismisses the whole sheet at once with no Home flash.
struct WeightsStartView: View {
    let onQuickStart: () -> Void
    /// Quick Start, but preceded by a guided warm-up timer (feedback batch 4).
    let onWarmupStart: () -> Void
    let onReuse: (WorkoutSession) -> Void
    /// Launches a library preset, optionally with a chosen per-set rep ladder
    /// (flexible templates carry one; fixed programs pass nil).
    let onPlan: (WorkoutPlan, [Int]?) -> Void

    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    /// Recent weight-only sessions (non-CrossFit) that have logged sets, newest
    /// first, capped at the last 20.
    private var previous: [WorkoutSession] {
        Array(sessions.filter { s in
            !s.orderedSets.isEmpty
                && s.planKey.flatMap { PlanCatalog.plan(forKey: $0)?.source } != .crossfit
        }.prefix(20))
    }

    var body: some View {
        List {
            Section {
                Button(action: onQuickStart) {
                    Label("Quick Start", systemImage: "bolt.fill").font(.headline)
                }
                .accessibilityIdentifier("weights.quickStart")
                Button(action: onWarmupStart) {
                    Label("Start with Warm-Up", systemImage: "figure.cooldown").font(.headline)
                }
                .accessibilityIdentifier("weights.warmupStart")
            } footer: {
                Text("Start a blank workout and add exercises as you go — or warm up first.")
            }

            Section("Start from Previous Workout") {
                if previous.isEmpty {
                    Text("No previous weight workouts yet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(previous) { s in
                    Button { onReuse(s) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title.isEmpty ? "Workout" : s.title).font(.headline)
                            Text("\(s.date.formatted(date: .abbreviated, time: .omitted)) · \(s.exercisesInOrder.count) exercises · \(s.orderedSets.count) sets")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("weights.previousRow")
                }
            }

            Section("Start from Library") {
                ForEach(StrengthPresets.all) { plan in
                    NavigationLink {
                        // Flexible templates pick a set/rep scheme first; fixed
                        // programs (5×5, Olympic) go straight to the preview.
                        if plan.flexibleScheme {
                            RepSchemePicker(plan: plan, onStart: onPlan)
                        } else {
                            CrossFitPreviewView(plan: plan) { onPlan(plan, nil) }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.name).font(.headline)
                            Text(plan.movementNames.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("weights.library.\(plan.id)")
                }
            }
        }
        .navigationTitle("Strength")
        .navigationBarTitleDisplayMode(.inline)
    }
}
