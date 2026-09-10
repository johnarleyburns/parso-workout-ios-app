import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension PlanningView {
// MARK: - Routines

    var routinesList: some View {
        List {
            Section("My plans") {
                let plans = authoredPlans
                if plans.isEmpty {
                    Text("Build a week from scratch, then start any session from the plan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(plans) { plan in
                    Button {
                        manualPlan = plan
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.title).font(.headline)
                            Text(planSummary(plan))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("planning.authoredPlan.\(plan.id.raw.uuidString)")
                }
                Button {
                    manualPlan = ManualPlanBuilder.blankPlan()
                } label: {
                    Label("New blank week", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("planning.newBlankWeek")
            }

            if trimmedQuery.isEmpty {
                if !favoriteRoutines.isEmpty {
                    Section("Favorites") {
                        ForEach(favoriteRoutines) { routineRow($0) }
                    }
                }
                routineGroupSection("5\u{00d7}5 Program", plans: PlanningRoutineGroup.fiveByFive)
                routineGroupSection("5/3/1", plans: PlanningRoutineGroup.fiveThreeOne)
                routineGroupSection("DUP", plans: PlanningRoutineGroup.dup)
                routineGroupSection("Linear Periodization", plans: PlanningRoutineGroup.linearPeriodization)
                routineGroupSection("Cluster Set Training", plans: PlanningRoutineGroup.clusterSets)
                routineGroupSection("PPL (6-Day)", plans: PlanningRoutineGroup.ppl)
                routineGroupSection("Split Templates", plans: PlanningRoutineGroup.splits)
                routineGroupSection("Calisthenics", plans: PlanningRoutineGroup.calisthenics)
                routineGroupSection("Olympic Lifting", plans: PlanningRoutineGroup.olympic)
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

    var authoredPlans: [Plan] {
        persistedPlans.compactMap { record in
            guard let plan = try? record.decodedPlan(), plan.provenance == .selfAuthored else {
                return nil
            }
            return plan
        }
    }

    func planSummary(_ plan: Plan) -> String {
        let sessions = plan.weeks.flatMap(\.days).flatMap(\.sessions)
        let count = sessions.count
        return "\(count) session\(count == 1 ? "" : "s") · \(plan.status == .active ? "Active" : "Draft")"
    }

    func startAuthoredSession(_ session: Session) {
        guard active.liveWorkout.active == nil else { return }
        if session.executionBoundary.canStartCombinedRunner {
            startCombinedSession(session)
            return
        }
        guard session.executionBoundary.canStartStrengthRunner else { return }
        let names = session.orderedItems.compactMap { item -> (String, String)? in
            guard case let .strength(strength) = item else { return nil }
            let key = strength.exerciseKey.raw
            let name = ExerciseLibrary.starter.first {
                $0.sourceExerciseID == key || ExerciseLibrary.lookupKey($0.name) == key
            }?.name ?? key.replacingOccurrences(of: "_", with: " ").capitalized
            return (key, name)
        }
        do {
            let runtime = try WorkoutRepository.startSession(
                from: session,
                athlete: AthleteExecutionSnapshot(),
                exerciseNameByKey: Dictionary(names, uniquingKeysWith: { first, _ in first }),
                in: context)
            guard active.startStrength(runtime) else {
                runtime.deletedAt = Date()
                try? context.save()
                return
            }
            WorkoutCues.singleStart(enabled: settings.workoutSounds)
            manualPlan = nil
            switchToWorkout()
        } catch {
            // The runtime adapter owns validation of prescription loads. An
            // authored plan remains saved and editable if a start is rejected.
        }
    }

    func startCombinedSession(_ session: Session) {
        let intent = LiveWorkoutStartIntent(
            kind: .combinedPlan(id: session.id),
            routePayload: "combined-plan",
            origin: .plan)
        guard case let .granted(lease) = active.liveWorkout.requestStart(
            intent: intent, descriptorName: session.title) else { return }
        combinedLaunch = CombinedSessionLaunch(session: session, lease: lease)
    }

    func routineGroupSection(_ title: String, plans: [WorkoutPlan]) -> some View {
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

    func routineRow(_ plan: WorkoutPlan) -> some View {
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
