import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension ExercisePickerView {
    /// The single planning-mode selection path: rows, detail, best match and
    /// custom creation all land here. Deliberately never dismisses.
    func addToPlanningDraft(_ exercise: Exercise) {
        do {
            let draft = try planningDrafts.add(exercise, to: nil, in: context)
            Haptics.selection()
            refreshDraftState(draft)
        } catch {
            planningDraftError = error.localizedDescription
        }
    }

    func refreshDraftState(_ known: PlanningDraft? = nil) {
        do {
            guard let draft = try known ?? planningDrafts.currentDraft(in: context) else {
                draftNames = []; draftSummary = nil
                return
            }
            let names = try planningDrafts.exerciseNames(for: draft)
            draftNames = Set(names.map { $0.lowercased() })
            draftSummary = PlanningDraftSummary(id: draft.id, title: draft.title, exerciseCount: names.count)
        } catch {
            planningDraftError = error.localizedDescription
        }
    }

    @ViewBuilder
    func routeDestination(_ route: ExerciseDetailRoute) -> some View {
        switch route {
        case .exercise(let id):
            if let exercise = ExerciseCatalogSnapshot.exercise(id: id, in: context) {
                if isFind {
                    ExerciseDetailView(
                        exercise: exercise,
                        actionTitle: draftNames.contains(exercise.name.lowercased())
                            ? String(localized: "Added to workout draft")
                            : String(localized: "Add to workout draft"),
                        onPick: { addToPlanningDraft($0) },
                        dismissesAfterPick: false)
                        .navigationTransition(.zoom(sourceID: id, in: searchTransition))
                } else {
                    ExerciseDetailView(exercise: exercise, actionTitle: action.detailActionTitle) { picked in
                        completion?(picked)
                        dismiss()
                    }
                    .navigationTransition(.zoom(sourceID: id, in: searchTransition))
                }
            } else {
                ContentUnavailableView(
                    "Exercise unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This exercise is no longer available in the local catalog. Return and try again."))
            }
        case .draft:
            WorkoutDraftView()
        }
    }

    var draftSummaryBar: some View {
        let count = draftSummary?.exerciseCount ?? 0
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PlanningDraftSummary.countText(count)).font(.subheadline.weight(.semibold))
                Text(PlanningDraftSummary.headline(draftSummary))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("find.draftSummary")
            Button("View draft") { path.append(.draft) }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .accessibilityLabel("View workout draft, \(PlanningDraftSummary.countText(count))")
                .accessibilityIdentifier("find.viewDraft")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
    }
}
