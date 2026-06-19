import SwiftUI
import SwiftData
import CadenceCore

struct WeightsStartView: View {
    let onEditorStart: (EditablePlan) -> Void
    var recommendation: Recommendation? = nil

    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Environment(AppSettings.self) private var settings

    private var previous: [WorkoutSession] {
        Array(sessions.filter { !$0.orderedSets.isEmpty }.prefix(20))
    }

    var body: some View {
        List {
            if let rec = recommendation {
                Section {
                    NavigationLink {
                        WorkoutPlanEditor(plan: .from(recommendation: rec), onStart: onEditorStart)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checklist").font(.title2)
                            Text("Coach's Workout").font(.title3.bold())
                            Spacer()
                        }
                        .padding(.vertical, 14).padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .foregroundStyle(.white)
                        .background(.green, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("weights.coachStart")
                    .accessibilityLabel("Coach's Workout")
                } footer: {
                    Text(rec.title)
                }
            }

            Section {
                NavigationLink {
                    WorkoutPlanEditor(
                        plan: .empty(warmup: 0, cooldown: settings.cooldownMinutes),
                        onStart: onEditorStart)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill").font(.title2)
                        Text("Quick Start").font(.title3.bold())
                        Spacer()
                        Image(systemName: "chevron.right").font(.subheadline).opacity(0.8)
                    }
                    .padding(.vertical, 16).padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .foregroundStyle(.white)
                    .background(LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("weights.quickStart")

                NavigationLink {
                    WorkoutPlanEditor(
                        plan: .empty(warmup: settings.warmupMinutes, cooldown: settings.cooldownMinutes),
                        onStart: onEditorStart)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "figure.cooldown").font(.headline)
                        Text("Start with Warm-Up").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.subheadline).opacity(0.6)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.tint)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
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
                    NavigationLink {
                        WorkoutPlanEditor(plan: .from(session: s), onStart: onEditorStart)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title.isEmpty ? "Workout" : s.title).font(.headline)
                            Text("\(s.date.formatted(date: .abbreviated, time: .omitted)) · \(s.exercisesInOrder.count) exercises · \(s.orderedSets.count) sets")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("weights.previousRow")
                }
            }

            Section("Start from Library") {
                ForEach(StrengthPresets.all) { plan in
                    NavigationLink {
                        if plan.flexibleScheme {
                            RepSchemePicker(plan: plan, onEditorStart: onEditorStart)
                        } else {
                            WorkoutPlanEditor(
                                plan: .from(plan: plan, ladder: nil, unit: settings.unit),
                                onStart: onEditorStart)
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

            Section {
                @Bindable var settings = settings
                Toggle("Use HR monitoring", isOn: $settings.useHRMonitoring)
                    .accessibilityIdentifier("weights.hrToggle")
            } footer: {
                Text("Connect a chest strap or Apple Watch before the workout starts.")
            }
        }
        .navigationTitle("Strength")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PlanPreviewView: View {
    let plan: WorkoutPlan
    var repLadder: [Int]? = nil
    let onStart: () -> Void
    @Environment(AppSettings.self) private var settings

    private var ladder: [Int]? {
        guard let repLadder, !repLadder.isEmpty else { return nil }
        return repLadder
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(plan.schemeSummary)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("plan.preview.scheme")

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
                .tint(.green)
                .controlSize(.large)
                .accessibilityIdentifier("plan.preview.start")
            }
            .padding()
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
