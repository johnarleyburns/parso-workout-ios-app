import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct RoutineDetailView: View {
    let plan: WorkoutPlan
    let onEditorStart: (EditablePlan) -> Void

    @Environment(AppSettings.self) private var settings
    @Query(sort: \Assessment.date, order: .reverse) private var assessments: [Assessment]

    private var e1RMs: [String: Double] {
        let summaries = AssessmentMath.summaries(from: assessments)
        var result: [String: Double] = [:]
        for s in summaries where s.kind == .e1RM {
            if let name = s.exerciseName, !name.isEmpty {
                result[name] = max(result[name] ?? 0, s.latest)
            }
        }
        return result
    }

    private var hasPercentageItems: Bool {
        plan.items.contains { $0.loadPercentage != nil }
    }

    private var missingE1RMMovements: [String] {
        plan.items.compactMap { item -> String? in
            guard item.loadPercentage != nil else { return nil }
            return e1RMs[item.movement] == nil ? item.movement : nil
        }
    }

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
                            let line = Format.prescription(item, ladder: nil, unit: settings.unit,
                                                           assessedE1RM: e1RMs[item.movement])
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

                if !missingE1RMMovements.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set your 1RM")
                                .font(.subheadline.weight(.semibold))
                            Text("Record a 1RM test for \(missingE1RMMovements.joined(separator: ", ")) to see computed loads.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("routine.missing1RM")
                }

                if let notes = plan.notes {
                    Text(notes).font(.footnote).foregroundStyle(.secondary)
                }

                if plan.flexibleScheme {
                    NavigationLink {
                        RepSchemePicker(plan: plan, onEditorStart: onEditorStart)
                    } label: {
                        Label("Choose Scheme & Start", systemImage: "play.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .cadenceGlassButton(prominent: true, tint: .green)
                    .accessibilityIdentifier("routine.chooseScheme")
                } else {
                    NavigationLink {
                        WorkoutPlanEditor(
                            plan: .from(plan: plan, ladder: nil, unit: settings.unit,
                                       warmupMinutes: settings.warmupMinutes, cooldownMinutes: settings.cooldownMinutes),
                            onStart: onEditorStart)
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .cadenceGlassButton(prominent: true, tint: .green)
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
}
