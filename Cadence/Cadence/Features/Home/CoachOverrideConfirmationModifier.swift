import SwiftUI
import CadenceCore

// MARK: - Coach override confirmation dialog

/// Confirmation dialog shown before the user relaxes coach guardrails
/// to close the week's volume deficits (P3, D5). Extracted from HomeView
/// to keep it under the test-pyramid ratchet ceiling.
extension View {
    func coachOverrideConfirmation(
        pending: Binding<[MuscleGroup: Double]?>,
        guardrails: @escaping () -> [String],
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Add the gaps anyway?",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Add to this week's plan", role: .none) { onConfirm() }
            Button("Cancel", role: .cancel) { pending.wrappedValue = nil }
        } message: {
            if let deficits = pending.wrappedValue {
                let parts = deficits.sorted { $0.key.displayName < $1.key.displayName }
                    .map { "\($0.key.displayName) +\(Int($0.value.rounded()))" }
                    .joined(separator: ", ")
                let g = guardrails().map { "  • \($0)" }.joined(separator: "\n")
                Text("Coach will replan this week to close: \(parts).\n\nTo fit them, Coach will go past its usual guardrails:\n\(g)\n\nYour call — Coach recommends, you decide. You can revert to the safe plan any time this week.")
            }
        }
    }
}

/// Scientific guardrails the coach will relax when the user accepts
/// the volume override (listed in the D5 confirmation sheet).
enum CoachOverrideGuardrails {
    static func describe(from diagnostics: [PlanningDiagnostic]) -> [String] {
        var items: [String] = []
        if diagnostics.contains(where: { $0.kind == .recoveryBlocked }) {
            items.append("may plan hard work before full recovery eligibility")
        }
        if diagnostics.contains(where: { $0.kind == .skippedRestDay }) {
            items.append("may skip a scheduled rest day")
        }
        if diagnostics.contains(where: { $0.kind == .noStrengthSlots }) {
            items.append("may need to schedule an extra strength session")
        }
        if items.isEmpty {
            items.append("may exceed the conservative per-session size")
        }
        return items
    }
}
