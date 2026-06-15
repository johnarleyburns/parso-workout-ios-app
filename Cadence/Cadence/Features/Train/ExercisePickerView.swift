import SwiftUI
import SwiftData
import CadenceCore

/// Searchable exercise library picker (FR-1.1, expanded feedback batch 8). To keep a
/// large catalog usable it leads with a curated **Popular** shortlist and hides the
/// long tail behind **Browse all** + search; a row of **body-part filter chips** and
/// muscle subtitles make movements discoverable ("show me lats"). Each row links out
/// to **EXRX.NET** in the system browser for full instructions (copyright-respecting —
/// we link, never embed). An inline "Create '<query>'" row adds a custom exercise.
struct ExercisePickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var query = ""
    @State private var selectedPart: BodyPart?
    @State private var browseAll = false
    let onPick: (Exercise) -> Void

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The popular shortlist, resolved against the seeded store (in catalog order).
    private var popular: [Exercise] {
        let byName = Dictionary(exercises.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        return ExerciseLibrary.popularNames.compactMap { byName[$0.lowercased()] }
    }

    /// What to show: a search beats everything; then a body-part filter; else the
    /// popular shortlist (until "Browse all" reveals the full grouped catalog).
    private var filtered: [Exercise] {
        if !trimmedQuery.isEmpty { return ExerciseSearch.rank(trimmedQuery, over: exercises) }
        if let part = selectedPart { return exercises.filter { $0.bodyParts.contains(part) } }
        return browseAll ? exercises : popular
    }

    private var grouped: [(ExerciseCategory, [Exercise])] {
        let dict = Dictionary(grouping: filtered) { $0.categoryValue ?? .other }
        return ExerciseCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items.sorted { $0.name < $1.name })
        }
    }

    private var exactMatchExists: Bool {
        exercises.contains { $0.name.compare(trimmedQuery, options: .caseInsensitive) == .orderedSame }
    }

    /// Group the flat list (search/filter/popular) into categories only when browsing
    /// the whole catalog; otherwise show one flat, ranked section.
    private var showsGrouped: Bool { browseAll && trimmedQuery.isEmpty && selectedPart == nil }

    var body: some View {
        NavigationStack {
            List {
                filterChips

                if !trimmedQuery.isEmpty && !exactMatchExists {
                    Section {
                        Button { create() } label: {
                            Label("Create “\(query)”", systemImage: "plus.circle.fill")
                        }
                        .accessibilityIdentifier("picker.create")
                    }
                }

                if showsGrouped {
                    ForEach(grouped, id: \.0) { cat, items in
                        Section(cat.displayName) { ForEach(items) { exerciseRow($0) } }
                    }
                } else {
                    Section(sectionTitle) { ForEach(filtered) { exerciseRow($0) } }
                    if !browseAll && trimmedQuery.isEmpty && selectedPart == nil {
                        Section {
                            Button { browseAll = true } label: {
                                Label("Browse all exercises", systemImage: "square.grid.2x2")
                            }
                            .accessibilityIdentifier("picker.browseAll")
                        }
                    }
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search name, muscle, or equipment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("picker.cancel")
                }
            }
        }
        .accessibilityIdentifier("picker.search")
    }

    private var sectionTitle: String {
        if !trimmedQuery.isEmpty { return "Results" }
        if let part = selectedPart { return part.displayName }
        return "Popular"
    }

    // MARK: Body-part filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: selectedPart == nil) { selectedPart = nil }
                    .accessibilityIdentifier("picker.filter.all")
                ForEach(BodyPart.allCases) { part in
                    chip(part.displayName, active: selectedPart == part) {
                        selectedPart = (selectedPart == part) ? nil : part
                    }
                    .accessibilityIdentifier("picker.filter.\(part.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 0))
    }

    private func chip(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
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

    // MARK: Rows

    private func exerciseRow(_ ex: Exercise) -> some View {
        HStack {
            Button {
                onPick(ex); dismiss()
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("picker.row.\(ex.name)")

            if let url = ExerciseLibrary.exrxReferenceURL(forName: ex.name) {
                Button { openURL(url) } label: {
                    Image(systemName: "info.circle").foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("picker.exrx.\(ex.name)")
                .accessibilityLabel("Look up \(ex.name) on EXRX")
            }
        }
    }

    /// Friendly muscle list from the exercise's primary muscles ("upper-chest" →
    /// "Upper Chest"), so a glance shows what it trains (batch 8).
    private func muscleSubtitle(_ ex: Exercise) -> String? {
        let ids = ex.primaryMuscles.isEmpty ? ex.muscleGroups : ex.primaryMuscles
        guard !ids.isEmpty else { return nil }
        return ids.prefix(3).map { id in
            id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }.joined(separator: ", ")
    }

    private func create() {
        let name = trimmedQuery
        guard !name.isEmpty else { return }
        if let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) {
            onPick(ex); dismiss()
        }
    }
}
