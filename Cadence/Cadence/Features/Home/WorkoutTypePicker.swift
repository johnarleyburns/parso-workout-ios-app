import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct WorkoutTypePicker: View {
    let onSelect: (WorkoutType) -> Void
    let onEditorStart: (EditablePlan) -> Void
    let onOtherCardio: (_ description: String, _ gps: Bool) -> Void
    var recommendation: Recommendation? = nil
    var types: [WorkoutType] = WorkoutType.allCases
    var title: String = "Start Workout"
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 16),
                           GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(types) { type in
                        switch type {
                        case .weights:
                            NavigationLink {
                                WeightsStartView(onEditorStart: onEditorStart,
                                                 recommendation: recommendation)
                            } label: { WorkoutHero(type: type) }
                                .buttonStyle(.plain)
                                .tapHaptic()
                                .accessibilityIdentifier("startType.\(type.rawValue)")
                                .accessibilityLabel(type.displayName)
                        case .other:
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

/// Unified entry sheet for Home. Strength choices are deliberately explicit;
/// cardio keeps the existing downstream setup and recorder routes.
struct SelectWorkoutView: View {
    let recommendation: Recommendation?
    let onEditorStart: (EditablePlan) -> Void
    let onSelect: (WorkoutType) -> Void
    let onOtherCardio: (_ description: String, _ gps: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    private var previous: [WorkoutSession] { Array(sessions.filter { !$0.orderedSets.isEmpty }.prefix(20)) }

    var body: some View {
        NavigationStack {
            List {
                Section("Strength") {
                    NavigationLink {
                        WorkoutPlanEditor(plan: .empty(warmup: 0, cooldown: settings.cooldownMinutes), onStart: onEditorStart)
                    } label: {
                        Label("Quick Start", systemImage: "bolt.fill")
                    }.accessibilityIdentifier("selectWorkout.quickStart")
                    NavigationLink {
                        WorkoutPlanEditor(plan: recommendation.map {
                            .from(recommendation: $0, goal: settings.trainingGoal,
                                  warmupMinutes: settings.warmupMinutes,
                                  cooldownMinutes: settings.cooldownMinutes)
                        } ?? .empty(warmup: settings.warmupMinutes, cooldown: settings.cooldownMinutes), onStart: onEditorStart)
                    } label: {
                        Label("Coach’s Workout", systemImage: "wand.and.stars")
                    }.accessibilityIdentifier("selectWorkout.coach")
                    if previous.isEmpty {
                        Label("No previous strength workouts", systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(previous) { session in
                            NavigationLink {
                                WorkoutPlanEditor(plan: .from(session: session), onStart: onEditorStart)
                            } label: {
                                Label(session.title.isEmpty ? "Previous Workout" : session.title,
                                      systemImage: "clock.arrow.circlepath")
                            }
                            .accessibilityIdentifier("selectWorkout.previous")
                            .accessibilityValue(session.id.uuidString)
                        }
                    }
                }
                Section("Cardio") {
                    ForEach([WorkoutType.run, .walk, .cycle, .swim, .hiit, .boxing]) { type in
                        Button { onSelect(type) } label: {
                            Label(type.displayName, systemImage: type.symbol)
                        }
                        .accessibilityIdentifier("startType.\(type.rawValue)")
                    }
                    NavigationLink {
                        OtherCardioEntryView(onStart: onOtherCardio)
                    } label: {
                        Label("Other Cardio", systemImage: WorkoutType.other.symbol)
                    }
                }
            }
            .navigationTitle("Select Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

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
                Image(systemName: type.symbol).scaledSystemFont(30, relativeTo: .title, weight: .bold)
                Text(type.displayName).font(.title3.bold())
                if type.usesGPS { Text("GPS").font(.caption2).opacity(0.85) }
            }
            .foregroundStyle(.white)
            .padding(12)
            .cadenceGlassIfAvailable(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                interactive: true)
            .padding(2)
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
