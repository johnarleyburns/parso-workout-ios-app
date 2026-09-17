import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension WorkoutPlanEditor {
    /// Fills every partner's plan from *their* history for the owner's
    /// exercises. Runs on appear, roster changes, and after exercise changes.
    func resolvePartnerPlans() {
        let roster = rosterMembers()
        guard !plan.exercises.isEmpty else { return }
        let index: WorkoutPlanPartnerHistory.Index
        if let historyIndex {
            index = historyIndex
        } else {
            index = WorkoutPlanPartnerHistory.Index(context: modelContext)
            historyIndex = index
        }
        plan = PartnerPlanResolver.fill(plan: plan, roster: roster) { name, performerID in
            index.history(forExerciseNamed: name, performerID: performerID, people: allPeople)
        }
    }

    private func rosterMembers() -> [PartnerPlanResolver.RosterMember] {
        let peopleByID = Dictionary(allPeople.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = plan.partnerIDs.compactMap { id -> PartnerPlanResolver.RosterMember? in
            guard let person = peopleByID[id] else { return nil }
            return PartnerPlanResolver.RosterMember(performerID: person.isMe ? nil : person.id,
                                                    name: person.isMe ? "Me" : person.name)
        }
        let hasPartner = ordered.contains { $0.performerID != nil }
        guard hasPartner else { return [.init(performerID: nil, name: "Me")] }
        if ordered.contains(where: { $0.performerID == nil }) { return ordered }
        return [.init(performerID: nil, name: "Me")] + ordered
    }

    func applyPickedExercise(_ exercise: Exercise, for intent: ExercisePickerIntent) {
        switch intent {
        case .add:
            plan.exercises.append(EditableExercise(name: exercise.name,
                                                    sets: ownerSeedSets(for: exercise.name),
                                                    notes: ""))
        case .swap(let id):
            guard let index = plan.exercises.firstIndex(where: { $0.id == id }) else { return }
            plan.exercises[index].name = exercise.name
        }
        resolvePartnerPlans()
    }

    private func ownerSeedSets(for name: String) -> [EditableSet] {
        PartnerPlanResolver.ownerSeedSets(
            history: WorkoutPlanPartnerHistory.history(forExerciseNamed: name,
                                                       performerID: nil,
                                                       people: allPeople,
                                                       context: modelContext),
            defaultReps: 10)
    }
}

extension View {
    /// Home's card treatment so plan editor rows retain the dashboard rhythm.
    func workoutPlanCard() -> some View {
        padding(CGFloat(LayoutMetrics.cardPadding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .green)
    }
}
