import SwiftUI
import SwiftData
import CadenceCore

/// The Weights entry point (round4b feedback #1). Three ways to begin a strength
/// session: **Quick Start** (a blank workout), **Start from Previous Workout**
/// (one of your recent sessions, reused as a template), or **Start from Library**
/// (a built-in split — 5×5, Push/Pull/Legs, body-part days, Olympic). Pushed
/// inside the Start-Workout sheet, so launching is the parent's job and dismisses
/// the whole sheet at once with no Home flash.
struct WeightsStartView: View {
    let onQuickStart: () -> Void
    /// Quick Start, but preceded by a guided warm-up timer (feedback batch 4).
    let onWarmupStart: () -> Void
    let onReuse: (WorkoutSession) -> Void
    /// Launches a library preset, optionally with a chosen per-set rep ladder
    /// (flexible templates carry one; fixed programs pass nil).
    let onPlan: (WorkoutPlan, [Int]?) -> Void
    var recommendation: Recommendation? = nil
    var onCoachStart: ((Recommendation) -> Void)? = nil

    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Environment(AppSettings.self) private var settings

    /// Recent sessions that have logged sets, newest first, capped at the last 20.
    private var previous: [WorkoutSession] {
        Array(sessions.filter { !$0.orderedSets.isEmpty }.prefix(20))
    }

    var body: some View {
        List {
            if let rec = recommendation, let action = onCoachStart {
                Section {
                    Button { Haptics.selection(); action(rec) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checklist").font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Coach Workout").font(.title3.bold())
                                Text(rec.action)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.subheadline).opacity(0.8)
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
                    .accessibilityLabel("Coach Workout — \(rec.title)")
                } footer: {
                    Text(rec.title)
                }
            }

            Section {
                // Quick Start is the primary, positive action — green & prominent,
                // mirroring Home's "Start Workout" (feedback batch 7 item 4).
                Button { Haptics.selection(); onQuickStart() } label: {
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

                // Start with Warm-Up is the quieter secondary, like Home's "Log Workout".
                Button { Haptics.selection(); onWarmupStart() } label: {
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
                    Button { Haptics.selection(); onReuse(s) } label: {
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
                        if plan.flexibleScheme {
                            RepSchemePicker(plan: plan, onStart: onPlan)
                        } else {
                            PlanPreviewView(plan: plan) { onPlan(plan, nil) }
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

/// A read-only prescription preview for one strength preset, with a big Start
/// button. A flexible template's chosen per-set rep ladder (feedback batch 3) is
/// applied to every movement in the preview + the launched session.
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
