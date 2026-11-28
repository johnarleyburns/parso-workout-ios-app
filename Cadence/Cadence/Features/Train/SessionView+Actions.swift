import SwiftUI
import SwiftData
import UIKit
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

extension SessionView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if active.strengthSession?.id == session.id {
            ToolbarItem(placement: .topBarLeading) {
                Button { active.minimize() } label: { Image(systemName: "chevron.down") }
                    .accessibilityIdentifier("session.minimize")
                    .accessibilityLabel("Minimize workout")
            }
        } else {
            // Historical workouts can be opened in the root full-screen cover
            // from Summary. That presentation has no navigation Back button,
            // so always provide an explicit escape hatch for non-live editing.
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityIdentifier("session.close")
                    .accessibilityLabel("Close workout")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { volumeSummaryPresented = true } label: {
                    Label("Volume Summary", systemImage: "chart.bar.xaxis")
                }
                .accessibilityIdentifier("session.volumeSummary")
                .disabled(cache.state.contexts.isEmpty)
                if let plan {
                    NavigationLink {
                        RoutineDetailView(plan: plan, onEditorStart: { _ in })
                    } label: {
                        Label("Workout details", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("session.info")
                }
                Button {
                    editedTitle = session.title; renamePresented = true
                } label: { Label("Edit plan", systemImage: "pencil") }
                Button { managePartnersPresented = true } label: {
                    Label("Partners", systemImage: "person.2")
                }
                Button { workoutSettings = settings.lastStrengthSettings; workoutSettingsPresented = true } label: {
                    Label("Workout settings", systemImage: "gearshape")
                }
                Button { showHRInfo = true } label: {
                    Label("Receiving live HR", systemImage: "heart.text.square")
                }
                .accessibilityIdentifier("session.hrInfo")
                if active.strengthSession?.id == session.id {
                    Button { startCooldownAfterDialog() } label: {
                        Label("Start Cool Down", systemImage: "figure.cooldown")
                    }.accessibilityIdentifier("session.startCoolDown")
                }
                Button { Task { await saveToHealth() } } label: {
                    Label(healthSaved ? "Saved to Apple Health" : "Save to Apple Health",
                          systemImage: healthSaved ? "checkmark.circle.fill" : "heart.text.square")
                }
                .disabled(session.orderedSets.isEmpty)
                .accessibilityIdentifier("session.saveHealth")
                Divider()
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Delete workout", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityIdentifier("session.menu")
            .accessibilityLabel("Workout options")
        }
    }

    @ViewBuilder
    func plannedCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
            HStack {
                Text(name).font(.headline)
                    .accessibilityIdentifier("exerciseCard.\(name)")
                Spacer()
                Button {
                    if let ex = plannedExerciseIndex[name]
                        ?? (try? WorkoutRepository.findOrCreateExercise(named: name, in: context)) {
                        openInlineEditor(for: ex)
                    }
                } label: {
                    Image(systemName: "plus").font(.headline)
                        .foregroundStyle(.tint).frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("set.add.\(name)")
                .accessibilityLabel("Add set to \(name)")
                Menu {
                    if let ex = plannedExerciseIndex[name] {
                        Button {
                            detailExercise = ex
                        } label: {
                            Label("Exercise details", systemImage: "info.circle")
                        }
                        .accessibilityIdentifier("exercise.info.\(name)")
                    }
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
        }
        .padding(CGFloat(LayoutMetrics.cardPadding - 4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded)
    }
    /// The roster line is secondary context while training: keep it behind an
    /// explicit disclosure so the workout list stays focused on sets.
    var partnerDisclosure: some View {
        DisclosureGroup(isExpanded: $showPartnerDetails) {
            partnerBar
                .padding(.top, 6)
        } label: {
            Text(showPartnerDetails ? "Show less" : "Show more…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("session.partnerDetails")
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
    func recordActivity(meaningful: Bool = true) {
        guard active.strengthSession?.id == session.id else { return }
        active.recordActivityAutoResume()
        // Callers of recordActivity are genuine user actions (set/structure edits).
        if meaningful {
            active.recordMeaningfulActivity(.setMutation)
            try? context.save()
        }
    }
    func togglePause() {
        if active.isPaused {
            active.resume()
            timers.resume(now: Date())
        } else {
            timers.pause(now: Date())
            active.pause(origin: .manual)
        }
    }
    func endWorkout() {
        // The coordinator may already have ended this session at its inactivity deadline.
        if session.endReasonRaw == StrengthEndReason.inactivity.rawValue { return }
        WorkoutCues.endBeepSequence(enabled: settings.workoutSounds)
        RestAlarmCoordinator.shared.cancel()
        let recorderForEnd = active.heartRateRecorder
        recorderForEnd?.flush()
        model.stopWatchWorkout()
        if settings.autoSaveHealth, session.healthKitWorkoutUUID == nil, !session.orderedSets.isEmpty {
            Task { await saveToHealth() }
        }
        active.endStrength()
        timers.stop(now: Date())
        if let scheduledID = session.scheduledWorkoutID,
           let scheduled = try? context.fetch(FetchDescriptor<ScheduledWorkout>(
               predicate: #Predicate { $0.id == scheduledID })).first {
            _ = try? ScheduledWorkoutStore.markCompleted(recordID: scheduled.id, in: context)
        }
        try? context.save()
        // Final flush of the session-owned recorder; summary uses the persisted series.
        let recorder = recorderForEnd
        Task {
            if let recorder, !recorder.snapshot.isEmpty {
                let profile = await cardioIntensityProfile(model: model, settings: settings)
                active.finalizeHeartRate(profile: profile, sessionID: recorder.sessionID)
                AccessibilityNotification.Announcement(active.heartRatePendingSessionID == nil ? String(localized: "Cardio measurements saved.") : String(localized: "Waiting for cardio measurements. Retry from the summary.")).post()
            }
            active.finishedSummary = FinishedSummary(data: .from(session: session, hrSamples: session.hrSamplePoints), session: session)
        }
    }

    /// Phone-BLE strap readings enter the same recorder at observation time.
    /// Watch readings are captured by `AppModel` at the transport event.
    func sampleHR() {
        guard model.hrm.source == .bluetooth, let bpm = model.hrm.currentBPM, bpm > 0 else { return }
        active.heartRateRecorder?.record(HeartRateObservation(source: .phoneBLE, observedAt: Date(), bpm: bpm))
    }

    func saveToHealth() async {
        let sets = session.orderedSets
        guard let first = sets.first?.completedAt else { return }
        let last = sets.last?.completedAt ?? first
        // Full session bounds, so the measurement window is not truncated to the first/last set.
        let start = min(first, session.date)
        let end = max(last, session.endedAt ?? last, first.addingTimeInterval(60))
        let minutes = end.timeIntervalSince(start) / 60
        let kcal = max(30, round(CardioMath.strengthCaloriesPerMinute * minutes))
        let hrSamples = session.hrSamplePoints
        let bpmValues = hrSamples.map(\.bpm)
        let summary = StrengthWorkoutSummary(
            id: session.id, start: start, end: end,
            activeEnergyKcal: kcal, hrSamples: hrSamples,
            avgHR: bpmValues.isEmpty ? nil : bpmValues.reduce(0, +) / Double(bpmValues.count),
            maxHR: bpmValues.max(),
            metadata: CladironHealthBackup.strengthMetadata(for: session),
            updatedAt: session.updatedAt,
            effortScore: WorkoutEffort.strengthScore(
                workingSetRPEs: sets.filter { !$0.isWarmup }.compactMap(\.rpe)))
        let report = await model.healthBackup.enqueueAndDrain(.strength(summary))
        if let hkID = report.savedObjectIDs[session.id] {
            session.healthKitWorkoutUUID = hkID
            try? context.save()
            withAnimation { healthSaved = true }
        } else {
            withAnimation { healthSaved = false }
        }
    }
    func finishManualLog() { cleanupEmptyLog(); Haptics.selection(); onDone?() }

    func cleanupEmptyLog() {
        guard isManualLog, session.orderedSets.isEmpty else { return }
        if let scheduledID = session.scheduledWorkoutID {
            _ = try? ScheduledWorkoutStore.markAbandoned(recordID: scheduledID, in: context)
        }
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
        let exerciseSets = session.orderedSets
            .filter { $0.exercise?.id == exercise.id && !$0.isWarmup }
        let lastSet = exerciseSets.last
        let lastID = lastSet.map { $0.isOwnerSet ? nil : $0.performedBy?.id } ?? nil
        let id = SetAlternation.nextPerformerID(pendingSets: ctx?.pendingSets ?? [],
                                                rosterOrder: rosterOrder,
                                                lastLoggedPerformerID: lastID,
                                                hasLoggedWorkingSet: lastSet != nil)
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
        let partnerIDs = Set(allPeople.filter { !$0.isMe && !$0.isArchived }.map { $0.id.uuidString })
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

}
