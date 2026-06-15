import SwiftUI
import CadenceCore

/// The Start Workout type chooser. Visual hero cards (field-test round 3): a
/// type-keyed colour gradient with a large glyph, or a bundled photo if one is
/// dropped into the named asset slot (`hero-<type>`). Large + legible.
struct WorkoutTypePicker: View {
    /// A cardio/other type was chosen — the parent maps it to a launch.
    let onSelect: (WorkoutType) -> Void
    /// A strength-library preset was chosen — the parent launches the planned
    /// session, optionally with a chosen per-set rep ladder (flexible Strength
    /// templates carry one; everything else passes nil).
    let onPlan: (WorkoutPlan, [Int]?) -> Void
    /// Weights → Quick Start (a blank strength session).
    let onWeightsQuickStart: () -> Void
    /// Weights → Start with Warm-Up (a guided warm-up, then a blank session).
    let onWeightsWarmup: () -> Void
    /// Weights → Start from Previous (reuse a past session as a template).
    let onWeightsReuse: (WorkoutSession) -> Void
    /// "Other Cardio" chosen: free-text description + whether to GPS-track it
    /// (feedback batch 6 item 3).
    let onOtherCardio: (_ description: String, _ gps: Bool) -> Void
    /// Which types to offer; defaults to all. The Home "cardio min" tile passes the
    /// cardio-only subset for a focused quick-start (feedback batch 8).
    var types: [WorkoutType] = WorkoutType.allCases
    /// Sheet title — "Start Workout" by default, "Start Cardio" for the filtered tile.
    var title: String = "Start Workout"
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 16),
                           GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(types) { type in
                        // Weights pushes a chooser within this same sheet (feedback
                        // #1) — no sheet-swap, so Home doesn't flash behind it.
                        switch type {
                        case .weights:
                            NavigationLink {
                                WeightsStartView(onQuickStart: onWeightsQuickStart,
                                                 onWarmupStart: onWeightsWarmup,
                                                 onReuse: onWeightsReuse,
                                                 onPlan: onPlan)
                            } label: { WorkoutHero(type: type) }
                                .buttonStyle(.plain)
                                .tapHaptic()
                                .accessibilityIdentifier("startType.\(type.rawValue)")
                                .accessibilityLabel(type.displayName)
                        case .other:
                            // "Other Cardio" (feedback batch 6): a description +
                            // GPS-or-not entry, then the matching recorder.
                            NavigationLink {
                                OtherCardioEntryView(onStart: onOtherCardio)
                            } label: { WorkoutHero(type: type) }
                                .buttonStyle(.plain)
                                .tapHaptic()
                                .accessibilityIdentifier("startType.\(type.rawValue)")
                                .accessibilityLabel(type.displayName)
                        default:
                            Button { onSelect(type) } label: { WorkoutHero(type: type) }
                                .buttonStyle(.plain)
                                .tapHaptic()
                                .accessibilityIdentifier("startType.\(type.rawValue)")
                                .accessibilityLabel(type.displayName)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("startType.cancel")
                }
            }
        }
    }
}

/// A visual banner for a workout type — a colour gradient + glyph, overlaid by a
/// bundled photo (`hero-<type>`) when present. Falls back gracefully (no
/// licensing risk), so real Wikimedia/Commons images can be dropped in later.
struct WorkoutHero: View {
    let type: WorkoutType

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            gradient
            if let ui = UIImage(named: "hero-\(type.rawValue)") {
                Image(uiImage: ui).resizable().scaledToFill()
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.5)],
                                            startPoint: .top, endPoint: .bottom))
            }
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: type.symbol).font(.system(size: 30, weight: .bold))
                Text(type.displayName).font(.title3.bold())
                if type.usesGPS { Text("GPS").font(.caption2).opacity(0.85) }
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var gradient: some View {
        LinearGradient(colors: Self.colors(type), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func colors(_ type: WorkoutType) -> [Color] {
        switch type {
        case .weights: return [.indigo, .purple]
        case .run: return [.blue, .teal]
        case .walk: return [.teal, .green]
        case .cycle: return [.orange, .yellow]
        case .swim: return [.cyan, .blue]
        case .hiit: return [.pink, .red]
        case .boxing: return [.red, .orange]
        case .other: return [.gray, .blue]
        }
    }
}
