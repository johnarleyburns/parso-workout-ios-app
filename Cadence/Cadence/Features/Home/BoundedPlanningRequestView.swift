import SwiftUI
import CadenceCore

/// Review-first natural-language entry for the individual planning surface.
/// The request only applies typed planning intent and block metadata; the user
/// still authors the sessions and the deterministic coach remains the source of
/// any prescription.
struct BoundedPlanningRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    let onApply: (Plan) -> Void

    private var result: BoundedPlanningParseResult {
        BoundedPlanningRequestParser.parse(text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 96)
                        .accessibilityIdentifier("boundedPlan.text")
                    Text("Try: “4 days of hypertrophy with dumbbells for 45 minutes, 4 weeks, double progression.”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Describe your plan")
                } footer: {
                    Text("This is a bounded planning input. It sets intent and block shape for your review; it does not prescribe exercises, loads, or sets.")
                }

                if !result.unsupportedTerms.isEmpty {
                    Section {
                        Label(result.clarification ?? "That request is not supported.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("boundedPlan.unsupported")
                    }
                } else if let request = result.request {
                    reviewSection(request)
                    Section {
                        Button {
                            apply(request)
                        } label: {
                            Label("Review in planner", systemImage: "arrow.right.circle.fill")
                        }
                        .accessibilityIdentifier("boundedPlan.apply")
                    } footer: {
                        Text("You can add, edit, or remove every session after applying. Nothing is saved until you save the plan.")
                    }
                } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Label(result.clarification ?? "Add a supported planning detail.",
                              systemImage: "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("boundedPlan.clarification")
                    }
                }
            }
            .navigationTitle("Describe a plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("boundedPlan.cancel")
                }
            }
        }
    }

    @ViewBuilder
    private func reviewSection(_ request: PlanningRequest) -> some View {
        Section("Review") {
            LabeledContent("Goal", value: request.goal.displayName)
            LabeledContent("Experience", value: request.experience.displayName)
            LabeledContent("Days", value: "\(request.daysPerWeek) per week")
            if let minutes = request.sessionLengthMinutes {
                LabeledContent("Session length", value: "Up to \(minutes) minutes")
            }
            LabeledContent("Horizon", value: horizonText(request.horizon))
            if !request.equipmentProfile.isEmpty {
                LabeledContent("Equipment", value: request.equipmentProfile.map(\.displayName).joined(separator: ", "))
            }
            if let progression = request.progression {
                LabeledContent("Progression", value: progressionText(progression))
            }
            if let periodization = request.periodization {
                LabeledContent("Periodization", value: periodizationText(periodization))
            }
            if request.wantsConditioning {
                LabeledContent("Conditioning", value: "Included")
            }
            ForEach(request.constraints.indices, id: \.self) { index in
                LabeledContent("Constraint", value: constraintText(request.constraints[index]))
            }
        }
    }

    private func apply(_ request: PlanningRequest) {
        var plan = ManualPlanBuilder.blankPlan(
            title: "\(request.goal.displayName) plan")
        plan.goal = request.goal
        plan.planningRequest = request
        plan.notes = request.preferences.isEmpty
            ? nil
            : "Preferences: \(request.preferences.joined(separator: ", "))"

        if case let .mesocycle(weeks) = request.horizon, weeks > 1 {
            plan = (try? UnifiedPlanAuthoring.mesocycle(
                from: plan,
                weeks: weeks,
                periodization: request.periodization ?? .none,
                progression: request.progression)) ?? plan
        }
        onApply(plan)
        dismiss()
    }

    private func horizonText(_ horizon: PlanHorizon) -> String {
        switch horizon {
        case .singleWeek: return "One week"
        case let .mesocycle(weeks): return "\(weeks) weeks"
        case let .nativeCycle(days): return "\(days)-day rotation"
        }
    }

    private func progressionText(_ progression: ProgressionIntent) -> String {
        switch progression {
        case .linearLoad: return "Linear load"
        case .doubleProgression: return "Double progression"
        case .percentageBased: return "Percentage-based"
        case .autoregulated: return "Autoregulated"
        case .volume: return "Volume"
        }
    }

    private func periodizationText(_ periodization: PeriodizationModel) -> String {
        switch periodization {
        case .none: return "None"
        case .accumulationIntensificationDeload: return "Accumulation → intensification → deload"
        case .linear: return "Linear"
        case .dailyUndulating: return "Daily undulating"
        case .block: return "Block"
        }
    }

    private func constraintText(_ constraint: PlanningConstraint) -> String {
        switch constraint {
        case let .unavailableExercise(exercise): return "Avoid exercise \(exercise.raw)"
        case let .unavailableEquipment(equipment): return "Avoid \(equipment.displayName)"
        case let .avoidMovementPattern(pattern): return "Avoid \(pattern.displayName)"
        case let .avoidMuscleGroup(muscle): return "Avoid \(muscle.displayName)"
        case let .excludedWeekdays(days): return "Avoid \(days.map(\.displayName).joined(separator: ", "))"
        case let .maximumSessionMinutes(minutes): return "Maximum \(minutes) minutes"
        case let .note(note): return note
        }
    }
}
