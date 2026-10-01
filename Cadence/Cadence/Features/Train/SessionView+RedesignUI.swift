import SwiftUI
import CadenceCore
import CadenceFeatures

extension SessionView {
    func prMomentCard(_ moment: PRMoment) -> some View {
        let takeover = prEvent.map {
            PRMomentPresenter.takeover(for: $0, unit: settings.unit,
                                       performerName: moment.performerName)
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(CadenceTheme.achievement)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : setLoggedRevision)
                VStack(alignment: .leading, spacing: 2) {
                    Text(takeover?.headline ?? moment.headline).font(.headline)
                    Text(takeover?.exerciseName ?? moment.context)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            if let takeover {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(takeover.newValue).font(.title2.weight(.bold).monospacedDigit())
                    }
                    if let previous = takeover.previousValue {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Previous").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(previous).font(.subheadline.monospacedDigit())
                        }
                    }
                    Spacer(minLength: 4)
                    Text(takeover.ruleLabel).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if let improvement = takeover.improvement {
                    Text(improvement).font(.subheadline.weight(.semibold))
                        .foregroundStyle(CadenceTheme.achievement)
                }
            } else {
                Text(moment.context).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if let event = prEvent,
                   let url = ShareCardRenderer.render(event: event, unit: settings.unit) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button("Keep going") { prMoment = nil; prEvent = nil }
                    .buttonStyle(.borderedProminent)
                    .tint(CadenceTheme.accent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CadenceTheme.achievement.opacity(0.45)))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.prMoment")
    }

    var sessionTitleHeader: some View {
        let completed = cache.state.contexts.reduce(0) { count, context in
            count + context.sets.filter { !$0.isWarmup }.count
        }
        let planned = completed + cache.state.contexts.reduce(0) { count, context in
            count + context.pendingSets.count
        }
        let partners = attributablePartners.map(\.name).joined(separator: ", ")
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title.isEmpty ? String(localized: "Workout") : session.title)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                Text(partners.isEmpty ? "Strength session" : "with \(partners)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            ZStack {
                Circle().stroke(CadenceTheme.accent.opacity(0.18), lineWidth: 6)
                Circle().trim(from: 0, to: planned > 0 ? min(1, Double(completed) / Double(planned)) : 0)
                    .stroke(CadenceTheme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(completed)/\(planned)").font(.caption2.weight(.bold)).monospacedDigit()
            }
            .frame(width: 48, height: 48)
            .accessibilityLabel(SessionProgressPresenter.progress(completedWorkingSets: completed,
                                                                   plannedWorkingSets: planned).label)
        }
        .padding(.horizontal, 4)
        .accessibilityIdentifier("session.header")
    }

    @ViewBuilder
    func exerciseCardView(for ctx: SessionRenderModel.ExerciseContext) -> some View {
        let isActive = inlineExerciseID == ctx.exerciseID
        let exercise = exerciseForID(ctx.exerciseID)

        ExerciseCardView(
            context: ctx,
            prSetIDs: cache.state.prSetIDs,
            roster: rosterEntries,
            hasPartners: hasPartners,
            unit: settings.unit,
            prRule: settings.prRule,
            prescriptionText: exercise.map { prescription(for: $0.name) } ?? nil,
            isExpanded: expandedExerciseID == ctx.exerciseID,
            isCurrent: inlineExerciseID == ctx.exerciseID ||
                (inlineExerciseID == nil &&
                 cache.state.contexts.first(where: { !$0.pendingSets.isEmpty || !$0.pendingReps.isEmpty })?.exerciseID == ctx.exerciseID),
            compactSummary: compactSummary(for: ctx),
            rotorNamespace: sessionRotorNamespace,
            onToggleExpansion: {
                if reduceMotion {
                    expandedExerciseID = expandedExerciseID == ctx.exerciseID ? nil : ctx.exerciseID
                } else { withAnimation(.easeInOut(duration: 0.18)) {
                    expandedExerciseID = expandedExerciseID == ctx.exerciseID ? nil : ctx.exerciseID
                } }
            },
            isInlineActive: isActive,
            inlineEditingSetID: inlineEditingSetID,
            inlineConfig: isActive ? inlineEditorConfig() : nil,
            wouldBePR: { [cache] kg, reps in
                cache.state.wouldBePR(weightKg: kg, reps: reps, isWarmup: false,
                                      rule: settings.prRule, formula: settings.formula,
                                      for: ctx.exerciseID)
            },
            onTapSet: { set in
                expandedExerciseID = ctx.exerciseID
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                openInlineEditor(for: ex, editingSetID: set.setID)
            },
            onTapPending: { pending in
                expandedExerciseID = ctx.exerciseID
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                openInlineEditor(for: ex, repsOverride: pending.targetReps, performerID: pending.performerID)
            },
            onLogPending: { pending in
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                logPendingSet(pending, for: ex)
            },
            onTalkPressing: { pending, pressing in
                quickTalkPressing(pending, exercise: exerciseForID(ctx.exerciseID), pressing: pressing)
            },
            onRepeat: {
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                let sets = session.orderedSets.filter { $0.exercise?.id == ex.id }
                // In a partner workout, the interleaved pending queue is the
                // source of truth for whose turn it is. Never fall back to a
                // different performer's last set: that silently copies the
                // owner's set onto a partner when the partner has not logged
                // this exercise yet.
                let fallbackPerformerID = nextPerson(for: ex).flatMap { $0.isMe ? nil : $0.id }
                let performerID = SetAlternation.performerForRepeat(
                    pendingSets: ctx.pendingSets,
                    fallbackPerformerID: fallbackPerformerID)
                guard let last = sets.last(where: {
                    setPerformedBy($0, performerID: performerID)
                }) else { return }
                addSet(to: ex, weightKg: last.weight, reps: last.reps, rpe: last.rpe,
                       isWarmup: last.isWarmup, usesBodyweight: last.usesBodyweight,
                       note: nil, performedBy: people(for: performerID))
            },
            onAddSet: {
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                openInlineEditor(for: ex)
            },
            onChangeExercise: {
                if let ex = exerciseForID(ctx.exerciseID) { swapTarget = .logged(exerciseID: ex.id) }
            },
            onRemoveExercise: {
                if let ex = exerciseForID(ctx.exerciseID) { exerciseToRemove = ex }
            },
            exercise: exerciseForID(ctx.exerciseID),
            onSaveSet: { draft in
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                recordInlineSet(for: ex, draft: draft)
            },
            onDeleteEditingSet: { deleteInlineSet() },
            onDeleteSet: { set in
                guard let entry = session.orderedSets.first(where: { $0.id == set.setID }) else { return }
                try? WorkoutRepository.deleteSet(entry, in: context)
                recordActivity()
            },
            onCancelInline: { closeInlineEditor() },
            onActivity: { recordActivity() }
        )
    }
}
