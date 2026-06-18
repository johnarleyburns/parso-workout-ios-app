import SwiftUI
import SwiftData
import CadenceCore

struct RoutineDetailView: View {
    let plan: WorkoutPlan
    let switchToWorkout: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutModel.self) private var active
    @Environment(AppSettings.self) private var settings

    private var bodyParts: [BodyPart] {
        var parts = Set<BodyPart>()
        for name in plan.movementNames {
            if let t = ExerciseLibrary.byName[name.lowercased()] {
                parts.formUnion(ExerciseLibrary.bodyParts(of: t))
            }
        }
        return BodyPart.allCases.filter { parts.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    tag(plan.schemeSummary)
                    if plan.flexibleScheme { tag("Flexible") }
                }

                if !bodyParts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Targets").font(.subheadline.weight(.semibold))
                        Text(bodyParts.map(\.displayName).joined(separator: ", "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("routine.bodyParts")
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.items) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.movement).font(.headline)
                            let line = Format.prescription(item, ladder: nil, unit: settings.unit)
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

                if plan.flexibleScheme {
                    NavigationLink {
                        RepSchemePicker(plan: plan) { plan, ladder in
                            startWorkout(plan: plan, ladder: ladder)
                        }
                    } label: {
                        Label("Choose Scheme & Start", systemImage: "play.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("routine.chooseScheme")
                } else {
                    Button { startWorkout(plan: plan, ladder: nil) } label: {
                        Label("Start", systemImage: "play.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    .accessibilityIdentifier("routine.start")
                }
            }
            .padding()
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("routine.detail")
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(.tint)
    }

    private func startWorkout(plan: WorkoutPlan, ladder: [Int]?) {
        if let session = try? WorkoutRepository.startSession(from: plan, repLadder: ladder, in: context) {
            active.startStrength(session)
            WorkoutCues.startBeepSequence(enabled: settings.workoutSounds)
            Haptics.selection()
            switchToWorkout()
        }
    }
}
