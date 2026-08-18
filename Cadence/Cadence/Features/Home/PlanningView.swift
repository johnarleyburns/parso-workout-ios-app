import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct PlanningView: View {
    let switchToWorkout: () -> Void
    /// Opens the Coach preview. Present in every coach surface state (including
    /// `hidden`), so the coach is always reachable from Programs (design §2/§8).
    var onOpenCoach: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutModel.self) private var active
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \SessionTemplate.name) private var templates: [SessionTemplate]

    @State private var segment: Segment = .routines
    @State private var query = ""
    @State private var selectedPart: BodyPart?
    @State private var browseAll = false
    @State private var templateEditorPresented = false

    enum Segment: String, CaseIterable { case routines, exercises }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Exercise filtering

    private var popular: [Exercise] {
        let byName = Dictionary(exercises.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        return ExerciseLibrary.popularNames.compactMap { byName[$0.lowercased()] }
    }

    private var filteredExercises: [Exercise] {
        if !trimmedQuery.isEmpty { return ExerciseSearch.rank(trimmedQuery, over: exercises) }
        if let part = selectedPart { return exercises.filter { $0.bodyParts.contains(part) } }
        return browseAll ? exercises : popular
    }

    private var grouped: [(ExerciseCategory, [Exercise])] {
        let dict = Dictionary(grouping: filteredExercises) { $0.categoryValue ?? .other }
        return ExerciseCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items.sorted { $0.name < $1.name })
        }
    }

    private var showsGrouped: Bool { browseAll && trimmedQuery.isEmpty && selectedPart == nil }

    private var exerciseSectionTitle: String {
        if !trimmedQuery.isEmpty { return "Results" }
        if let part = selectedPart { return part.displayName }
        return "Popular"
    }

    // MARK: Routine filtering

    private var filteredPresets: [WorkoutPlan] {
        guard !trimmedQuery.isEmpty else { return StrengthPresets.all }
        let q = trimmedQuery.lowercased()
        return StrengthPresets.all.filter {
            $0.name.lowercased().contains(q) ||
            $0.movementNames.contains { $0.lowercased().contains(q) }
        }
    }

    private var filteredTemplates: [SessionTemplate] {
        guard !trimmedQuery.isEmpty else { return templates }
        let q = trimmedQuery.lowercased()
        return templates.filter {
            $0.name.lowercased().contains(q) ||
            $0.orderedExercises.contains { $0.exerciseName.lowercased().contains(q) }
        }
    }

    private var favoriteRoutines: [WorkoutPlan] {
        settings.favoriteRoutineIDs.compactMap { PlanCatalog.plan(forKey: $0) }
            .sorted { $0.name < $1.name }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                Text("Routines").tag(Segment.routines)
                Text("Exercises").tag(Segment.exercises)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

            switch segment {
            case .routines: routinesList
            case .exercises: exercisesList
            }
        }
        .navigationTitle("Plan")
        .searchable(text: $query,
                    prompt: segment == .exercises
                        ? "Search name, muscle, or equipment"
                        : "Search routines")
        .onChange(of: segment) { _, _ in
            query = ""
            selectedPart = nil
            browseAll = false
        }
        .sheet(isPresented: $templateEditorPresented) { TemplateEditorView() }
        .accessibilityIdentifier("planning")
    }

    // MARK: - Exercises

    private var exercisesList: some View {
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
                if !browseAll && trimmedQuery.isEmpty && selectedPart == nil {
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

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: selectedPart == nil) { selectedPart = nil }
                    .accessibilityIdentifier("planning.filter.all")
                ForEach(BodyPart.allCases) { part in
                    chip(part.displayName, active: selectedPart == part) {
                        selectedPart = (selectedPart == part) ? nil : part
                    }
                    .accessibilityIdentifier("planning.filter.\(part.rawValue)")
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

    private func exerciseRow(_ ex: Exercise) -> some View {
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

    private func muscleSubtitle(_ ex: Exercise) -> String? {
        let ids = ex.primaryMuscles.isEmpty ? ex.muscleGroups : ex.primaryMuscles
        guard !ids.isEmpty else { return nil }
        return ids.prefix(3).map { id in
            id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }.joined(separator: ", ")
    }

    @State private var routineInfoSheet: RoutineInfo?

    // MARK: - Routines

    private var routinesList: some View {
        List {
            if trimmedQuery.isEmpty {
                if !favoriteRoutines.isEmpty {
                    Section("Favorites") {
                        ForEach(favoriteRoutines) { routineRow($0) }
                    }
                }
                routineGroupSection("5\u{00d7}5 Program", plans: RoutineGroup.fiveByFive)
                routineGroupSection("5/3/1", plans: RoutineGroup.fiveThreeOne)
                routineGroupSection("DUP", plans: RoutineGroup.dup)
                routineGroupSection("Linear Periodization", plans: RoutineGroup.linearPeriodization)
                routineGroupSection("Cluster Set Training", plans: RoutineGroup.clusterSets)
                routineGroupSection("PPL (6-Day)", plans: RoutineGroup.ppl)
                routineGroupSection("Split Templates", plans: RoutineGroup.splits)
                routineGroupSection("Calisthenics", plans: RoutineGroup.calisthenics)
                routineGroupSection("Olympic Lifting", plans: RoutineGroup.olympic)
            } else {
                if !filteredPresets.isEmpty {
                    Section("Routines") {
                        ForEach(filteredPresets) { routineRow($0) }
                    }
                }
            }

            Section {
                if filteredTemplates.isEmpty && trimmedQuery.isEmpty {
                    ContentUnavailableView("No templates yet",
                                           systemImage: "square.stack.3d.up",
                                           description: Text("Save a reusable day like \u{201c}Push Day\u{201d}."))
                }
                ForEach(filteredTemplates) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(.headline)
                        Text(t.orderedExercises.map(\.exerciseName).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .accessibilityIdentifier("planning.template.\(t.name)")
                    .swipeActions {
                        Button(role: .destructive) {
                            try? WorkoutRepository.deleteTemplate(t, in: context)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                Button { templateEditorPresented = true } label: {
                    Label("New Template", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("planning.newTemplate")
            } header: {
                Text("My Templates")
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $routineInfoSheet) { info in
            RoutineInfoSheet(info: info)
        }
    }

    private func routineGroupSection(_ title: String, plans: [WorkoutPlan]) -> some View {
        Section {
            ForEach(plans) { routineRow($0) }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button { routineInfoSheet = RoutineInfoCatalog.info(forGroup: title) } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) info")
            }
        }
    }

    private func routineRow(_ plan: WorkoutPlan) -> some View {
        NavigationLink {
            RoutineDetailView(plan: plan, onEditorStart: { edited in
                guard active.liveWorkout.active == nil else { return }
                guard let session = try? WorkoutRepository.createSession(title: edited.title, in: context) else { return }
                edited.apply(to: session)
                for name in edited.exercises.map(\.name) {
                    _ = try? WorkoutRepository.findOrCreateExercise(named: name, in: context)
                }
                session.cooldownSeconds = Double(edited.cooldownMinutes * 60)
                try? context.save()
                guard active.startStrength(session) else { session.deletedAt = Date(); return }
                WorkoutCues.startBeepSequence(enabled: settings.workoutSounds)
                Haptics.selection()
                switchToWorkout()
            })
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name).font(.headline)
                Text(plan.movementNames.joined(separator: " \u{00b7} "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .leading) {
            Button { settings.toggleFavoriteRoutine(plan.id) } label: {
                Label(settings.isRoutineFavorite(plan.id) ? "Unfavorite" : "Favorite",
                      systemImage: settings.isRoutineFavorite(plan.id) ? "heart.slash" : "heart")
            }
            .tint(.pink)
        }
        .accessibilityIdentifier("planning.routine.\(plan.id)")
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
