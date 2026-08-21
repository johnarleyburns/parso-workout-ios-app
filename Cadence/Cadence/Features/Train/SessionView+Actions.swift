import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension SessionView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if active.strengthSession?.id == session.id {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    active.minimize()
                } label: { Image(systemName: "chevron.down") }
                    .accessibilityIdentifier("session.minimize")
                    .accessibilityLabel("Minimize workout")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                if let plan {
                    NavigationLink {
                        RoutineDetailView(plan: plan, onEditorStart: { _ in })
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityIdentifier("session.info")
                    .accessibilityLabel("Workout details")
                }
                Button {
                    showDeleteConfirm = true
                } label: { Image(systemName: "trash") }
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("session.delete")
                    .accessibilityLabel("Delete workout")
                Button {
                    editedTitle = session.title; renamePresented = true
                } label: { Image(systemName: "pencil") }
                    .accessibilityIdentifier("session.rename")
                    .accessibilityLabel("Rename workout")
                Button {
                    Task { await saveToHealth() }
                } label: {
                    Image(systemName: healthSaved ? "checkmark.circle.fill" : "heart.text.square")
                }
                .disabled(session.orderedSets.isEmpty)
                .accessibilityIdentifier("session.saveHealth")
                .accessibilityLabel(healthSaved ? "Saved to Apple Health" : "Save workout to Apple Health")
            }
        }
    }
    @ViewBuilder
    func plannedCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
            HStack {
                Text(name).font(.headline)
                    .accessibilityIdentifier("exerciseCard.\(name)")
                Spacer()
                if let ex = plannedExerciseIndex[name] {
                    NavigationLink {
                        ExerciseDetailView(exercise: ex)
                    } label: {
                        Image(systemName: "info.circle").font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("exercise.info.\(name)")
                    .accessibilityLabel("\(name) details")
                }
                Menu {
                    Button { swapTarget = .planned(name: name) } label: {
                        Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        try? WorkoutRepository.removePlannedExercise(named: name, from: session, in: context)
                        recordActivity()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.headline)
                        .foregroundStyle(.secondary).frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("planned.menu.\(name)")
                .accessibilityLabel("Planned exercise options")
            }
            if let rx = prescription(for: name) {
                Text(rx).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("session.rx.\(name)")
            } else {
                Text("Planned — tap to log").font(.caption).foregroundStyle(.secondary)
            }
            if inlineExercise == nil || inlineExercise?.name != name {
                Button {
                    if let ex = plannedExerciseIndex[name]
                        ?? (try? WorkoutRepository.findOrCreateExercise(named: name, in: context)) {
                        openInlineEditor(for: ex)
                    }
                } label: { Label("Add Set", systemImage: "plus") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityIdentifier("set.add.\(name)")
            }
        }
        .padding(CGFloat(LayoutMetrics.cardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded)
    }
    var partnerBar: some View {
        HStack(spacing: 8) {
            Text("With:").font(.caption).foregroundStyle(.secondary)
            ForEach(roster) { p in
                performerChip(p)
                    .contextMenu {
                        if !p.isMe {
                            Button(role: .destructive) {
                                var ids = session.activePartnerIDs
                                ids.removeAll { $0 == p.id.uuidString }
                                session.activePartnerIDs = normalizedRosterIDs(ids)
                                try? context.save()
                            } label: { Label("Remove from session", systemImage: "person.slash") }
                        }
                    }
                if !p.isMe {
                    Text(p.name).font(.caption.weight(.medium)).padding(.horizontal, 6)
                }
            }
            Button {
                addPartnerPresented = true
            } label: { Image(systemName: "plus.circle") }
                .accessibilityIdentifier("partner.add").accessibilityLabel("Add training partner")
            Button {
                managePartnersPresented = true
            } label: { Image(systemName: "gearshape") }
                .accessibilityIdentifier("partner.manage").accessibilityLabel("Manage training partners")
            Spacer()
        }
    }
    func performerChip(_ p: Person?) -> some View {
        let label = (p?.isMe ?? true) ? "M" : String((p?.name ?? "?").prefix(1)).uppercased()
        let palette: [Color] = [.purple, .teal, .pink, .indigo, .orange, .mint]
        let color: Color = {
            guard let p, !p.isMe else { return .accentColor }
            return palette[abs(p.id.hashValue) % palette.count]
        }()
        return Text(label)
            .font(.caption2.weight(.semibold)).foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color, in: Circle())
            .accessibilityIdentifier("set.performer.\((p?.isMe ?? true) ? "Me" : (p?.name ?? "?"))")
    }
    func recordActivity() {
        watchdog.recordActivity()
        guard active.strengthSession?.id == session.id else { return }
        active.recordActivityAutoResume()
    }
    func handleIdleTick() {
        guard active.strengthSession?.id == session.id else { return }
        switch watchdog.tick(now: Date(),
                             timeoutMinutes: settings.idleTimeoutMinutes,
                             isPaused: active.isPaused,
                             enabled: settings.autoEndOnIdle) {
        case .showPrompt: idlePromptShown = true
        case .autoPause: idlePromptShown = false; active.pause(origin: .auto)
        case .none: break
        }
    }
    func togglePause() {
        if active.isPaused { active.resume(); watchdog.recordActivity() }
        else { active.pause(origin: .manual) }
    }
    func endWorkout() {
        WorkoutCues.endBeepSequence(enabled: settings.workoutSounds)
        model.stopWatchWorkout()
        if settings.autoSaveHealth, session.healthKitWorkoutUUID == nil, !session.orderedSets.isEmpty {
            Task { await saveToHealth() }
        }
        active.endStrength()
        try? context.save()
        Task { @MainActor in
            await Task.yield()
            active.finishedSummary = FinishedSummary(data: .from(session: session, hrSamples: hrSamples), session: session)
        }
    }

    func sampleHR() {
        guard let bpm = model.hrm.currentBPM, bpm > 0 else { return }
        let now = Date().timeIntervalSince(session.date)
        hrSamples.append(HRSamplePoint(t: now, bpm: bpm))
    }

    func saveToHealth() async {
        let sets = session.orderedSets
        guard let first = sets.first?.completedAt else { return }
        let last = sets.last?.completedAt ?? first
        let end = max(last, first.addingTimeInterval(60))
        let minutes = end.timeIntervalSince(first) / 60
        let kcal = max(30, round(CardioMath.strengthCaloriesPerMinute * minutes))
        let bpmValues = hrSamples.map(\.bpm)
        let summary = StrengthWorkoutSummary(
            id: session.id, start: first, end: end,
            activeEnergyKcal: kcal, hrSamples: hrSamples,
            avgHR: bpmValues.isEmpty ? nil : bpmValues.reduce(0, +) / Double(bpmValues.count),
            maxHR: bpmValues.max())
        let hkID = await model.health.saveStrengthWorkout(summary)
        if let hkID { session.healthKitWorkoutUUID = hkID; try? context.save() }
        withAnimation { healthSaved = true }
    }
    func finishManualLog() { cleanupEmptyLog(); Haptics.selection(); onDone?() }

    func cleanupEmptyLog() {
        guard isManualLog, session.orderedSets.isEmpty else { return }
        context.delete(session); try? context.save()
    }

    func swapPlannedExercise(oldName: String, newName: String) {
        guard oldName != newName else { return }
        var names = session.plannedExerciseNames
        if let idx = names.firstIndex(of: oldName) { names[idx] = newName }
        session.plannedExerciseNames = names
        _ = try? WorkoutRepository.findOrCreateExercise(named: newName, in: context)
        try? context.save()
        recordActivity()
    }
    func togglePartnerScope(_ p: Person) {
        var ids = explicitRosterIDs()
        if let idx = ids.firstIndex(of: p.id.uuidString) { ids.remove(at: idx) }
        else { ids.append(p.id.uuidString) }
        session.activePartnerIDs = normalizedRosterIDs(ids)
        try? context.save()
    }

    func addAndScopePartner() {
        let name = newPartnerName.trimmingCharacters(in: .whitespaces)
        defer { newPartnerName = "" }
        guard !name.isEmpty,
              let p = try? WorkoutRepository.findOrCreatePerson(named: name, in: context) else { return }
        var ids = explicitRosterIDs()
        if !ids.contains(p.id.uuidString) { ids.append(p.id.uuidString); session.activePartnerIDs = normalizedRosterIDs(ids); try? context.save() }
    }
    func nextPerson(for exercise: Exercise) -> Person? {
        guard hasPartners else { return nil }
        let ctx = cache.state.contexts.first { $0.exerciseID == exercise.id }
        let rosterOrder: [UUID?] = rosterEntries.map { $0.isMe ? nil : $0.personID }
        let lastID = session.orderedSets
            .filter { $0.exercise?.id == exercise.id && !$0.isWarmup }
            .last.map { $0.isOwnerSet ? nil : $0.performedBy?.id } ?? nil
        let id = SetAlternation.nextPerformerID(pendingSets: ctx?.pendingSets ?? [],
                                                rosterOrder: rosterOrder,
                                                lastLoggedPerformerID: lastID)
        return id.flatMap { people(for: $0) } ?? allPeople.first { $0.isMe }
    }
    func explicitRosterIDs() -> [String] {
        let current = session.activePartnerIDs
        guard hasPartners else { return current }
        let ids = roster.map { $0.id.uuidString }
        return ids.isEmpty ? current : ids
    }
    func normalizedRosterIDs(_ ids: [String]) -> [String] {
        let valid = Set(allPeople.map { $0.id.uuidString })
        var seen = Set<String>()
        let cleaned = ids.filter { valid.contains($0) && seen.insert($0).inserted }
        let partnerIDs = Set(allPeople.filter { !$0.isMe }.map { $0.id.uuidString })
        return cleaned.contains(where: { partnerIDs.contains($0) }) ? cleaned : []
    }

    func moveRosterMember(from index: Int, by offset: Int) {
        var ids = explicitRosterIDs()
        let target = index + offset
        guard ids.indices.contains(index), ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        session.activePartnerIDs = normalizedRosterIDs(ids)
        try? context.save()
    }

    func addSet(to exercise: Exercise, weightKg: Double, reps: Int,
                        rpe: Double?, isWarmup: Bool, usesBodyweight: Bool = false,
                        note: String?, performedBy: Person? = nil) {
        recordActivity()
        let person = (performedBy?.isMe ?? true) ? nil : performedBy
        let isPR = person == nil && WorkoutRepository.wouldBePR(exercise: exercise, weightKg: weightKg, reps: reps,
                                               isWarmup: isWarmup, rule: settings.prRule, formula: settings.formula)
        let when = session.isLogged ? session.date : Date()
        _ = try? WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: weightKg,
                                          reps: reps, rpe: rpe, isWarmup: isWarmup,
                                          usesBodyweight: usesBodyweight, note: note,
                                          completedAt: when, performedBy: person, in: context)
        if isPR { Haptics.prAchieved() } else { Haptics.setLogged() }
        if settings.autoStartRest && !isWarmup && !isManualLog && active.strengthSession?.id == session.id {
            rest.start(seconds: settings.restSeconds)
        }
    }
}
