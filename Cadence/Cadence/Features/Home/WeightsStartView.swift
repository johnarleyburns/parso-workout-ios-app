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
                        WorkoutPlanEditor(plan: .from(recommendation: rec,
                                                          warmupMinutes: settings.warmupMinutes,
                                                          cooldownMinutes: settings.cooldownMinutes), onStart: onEditorStart)
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
                libraryGroupSection("5\u{00d7}5 Program", plans: RoutineGroup.fiveByFive)
                libraryGroupSection("5/3/1", plans: RoutineGroup.fiveThreeOne)
                libraryGroupSection("DUP", plans: RoutineGroup.dup)
                libraryGroupSection("Linear Periodization", plans: RoutineGroup.linearPeriodization)
                libraryGroupSection("Cluster Set Training", plans: RoutineGroup.clusterSets)
                libraryGroupSection("PPL (6-Day)", plans: RoutineGroup.ppl)
                libraryGroupSection("Split Templates", plans: RoutineGroup.splits)
                libraryGroupSection("Calisthenics", plans: RoutineGroup.calisthenics)
                libraryGroupSection("Olympic Lifting", plans: RoutineGroup.olympic)
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

    private func libraryRow(_ plan: WorkoutPlan) -> some View {
        NavigationLink {
            if plan.flexibleScheme {
                RepSchemePicker(plan: plan, onEditorStart: onEditorStart)
            } else {
                WorkoutPlanEditor(
                    plan: .from(plan: plan, ladder: nil, unit: settings.unit,
                               warmupMinutes: settings.warmupMinutes,
                               cooldownMinutes: settings.cooldownMinutes),
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

    private func libraryGroupSection(_ title: String, plans: [WorkoutPlan]) -> some View {
        Section(title) {
            ForEach(plans) { libraryRow($0) }
        }
    }
}

private enum RoutineGroup {
    static let fiveByFive = StrengthPresets.all.filter { $0.id.hasPrefix("preset-5x5") }
    static let fiveThreeOne = StrengthPresets.all.filter { $0.id.hasPrefix("preset-531") }
    static let dup = StrengthPresets.all.filter { $0.id.hasPrefix("preset-dup") }
    static let linearPeriodization = StrengthPresets.all.filter { $0.id.hasPrefix("preset-lp") }
    static let clusterSets = StrengthPresets.all.filter { $0.id == "preset-cluster" }
    static let ppl = StrengthPresets.all.filter { $0.id.hasPrefix("preset-ppl") }
    static let splits = StrengthPresets.all.filter {
        ["preset-push", "preset-pull", "preset-legs", "preset-upper",
         "preset-lower", "preset-chest", "preset-back-bi"].contains($0.id)
    }
    static let calisthenics = StrengthPresets.all.filter { $0.id.hasPrefix("preset-cali") }
    static let olympic = StrengthPresets.all.filter { $0.id.hasPrefix("preset-oly") }
}
