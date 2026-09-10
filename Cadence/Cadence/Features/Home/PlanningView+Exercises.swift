import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension PlanningView {
    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

        // MARK: Exercise filtering

        var popular: [Exercise] {
            let byName = Dictionary(exercises.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
            return ExerciseLibrary.popularNames.compactMap { byName[$0.lowercased()] }
        }

        var filteredExercises: [Exercise] {
            if !trimmedQuery.isEmpty { return ExerciseSearch.rank(trimmedQuery, over: exercises) }
            if let group = selectedGroup { return exercises.filter { $0.trainedMuscleGroups.contains(group) } }
            return browseAll ? exercises : popular
        }

        var grouped: [(ExerciseCategory, [Exercise])] {
            let dict = Dictionary(grouping: filteredExercises) { $0.categoryValue ?? .other }
            return ExerciseCategory.allCases.compactMap { cat in
                guard let items = dict[cat], !items.isEmpty else { return nil }
                return (cat, items.sorted { $0.name < $1.name })
            }
        }

        var showsGrouped: Bool { browseAll && trimmedQuery.isEmpty && selectedGroup == nil }

        var exerciseSectionTitle: String {
            if !trimmedQuery.isEmpty { return "Results" }
            if let group = selectedGroup { return group.displayName }
            return "Popular"
        }

        // MARK: Routine filtering

        var filteredPresets: [WorkoutPlan] {
            guard !trimmedQuery.isEmpty else { return StrengthPresets.all }
            let q = trimmedQuery.lowercased()
            return StrengthPresets.all.filter {
                $0.name.lowercased().contains(q) ||
                $0.movementNames.contains { $0.lowercased().contains(q) }
            }
        }

        var filteredTemplates: [SessionTemplate] {
            guard !trimmedQuery.isEmpty else { return templates }
            let q = trimmedQuery.lowercased()
            return templates.filter {
                $0.name.lowercased().contains(q) ||
                $0.orderedExercises.contains { $0.exerciseName.lowercased().contains(q) }
            }
        }

        var favoriteRoutines: [WorkoutPlan] {
            settings.favoriteRoutineIDs.compactMap { PlanCatalog.plan(forKey: $0) }
                .sorted { $0.name < $1.name }
        }

    // MARK: - Exercises

        var exercisesList: some View {
            List {
                filterChips

                if showsGrouped {
                    ForEach(grouped, id: \.0) { cat, items in
                        Section(cat.displayName) {
                            ForEach(items) { exerciseRow($0) }
                        }
                    }
                } else {
                    Section(exerciseSectionTitle) {
                        ForEach(filteredExercises) { exerciseRow($0) }
                    }
                    if !browseAll && trimmedQuery.isEmpty && selectedGroup == nil {
                        Section {
                            Button { browseAll = true } label: {
                                Label("Browse all exercises", systemImage: "square.grid.2x2")
                            }
                            .accessibilityIdentifier("planning.browseAll")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }

        var filterChips: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", active: selectedGroup == nil) { selectedGroup = nil }
                        .accessibilityIdentifier("planning.filter.all")
                    ForEach(MuscleGroup.canonicalOrder) { group in
                        chip(group.displayName, active: selectedGroup == group) {
                            selectedGroup = (selectedGroup == group) ? nil : group
                        }
                        .accessibilityIdentifier("planning.filter.\(group.rawValue)")
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 0))
        }

        func chip(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
            Button { Haptics.selection(); tap() } label: {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.background.secondary),
                                in: Capsule())
                    .foregroundStyle(active ? .white : .primary)
            }
            .buttonStyle(.plain)
        }

        func exerciseRow(_ ex: Exercise) -> some View {
            NavigationLink {
                ExerciseDetailView(exercise: ex)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ex.name)
                        if ex.isCustom {
                            Text("Custom").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if let muscles = muscleSubtitle(ex) {
                        Text(muscles).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("planning.exercise.\(ex.name)")
            .swipeActions(edge: .leading) {
                Button { ex.isFavorite.toggle(); try? context.save() } label: {
                    Label(ex.isFavorite ? "Unfavorite" : "Favorite",
                          systemImage: ex.isFavorite ? "heart.slash" : "heart")
                }
                .tint(.pink)
            }
        }

        func muscleSubtitle(_ ex: Exercise) -> String? {
            let ids = ex.primaryMuscles.isEmpty ? ex.muscleGroups : ex.primaryMuscles
            guard !ids.isEmpty else { return nil }
            return ids.prefix(3).map { id in
                id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
            }.joined(separator: ", ")
        }
}
