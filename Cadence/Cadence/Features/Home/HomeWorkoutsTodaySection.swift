import SwiftUI
import CadenceCore
import CadenceFeatures

/// Home's "Workouts Today" card. Completed workouts open the same destination
/// This Week opens; coach-planned workouts expand in place to their full
/// prescription and can be started from there (field test 2026-08-18 #6).
struct HomeWorkoutsTodaySection: View {
    let rows: [WorkoutsTodayPresenter.Row]
    @Binding var expandedRowIDs: Set<String>
    let onOpenCompleted: (WorkoutsTodayPresenter.Row) -> Void
    let onStartPlanned: (WorkoutsTodayPresenter.Row) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.cardHeadingSpacing) {
            Text("Workouts Today").font(.headline)
            if rows.isEmpty {
                Text("Nothing completed or planned yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    if row.isNavigable {
                        HomeWeekWorkoutRow(row: row) { onOpenCompleted(row) }
                    } else {
                        HomePlannedWorkoutRow(
                            row: row,
                            isExpanded: expandedRowIDs.contains(row.id),
                            onToggle: { toggle(row) },
                            onStart: { onStartPlanned(row) })
                    }
                }
            }
        }
        .padding(LayoutMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .green)
        // `children: .contain` must precede the identifier or the styled card
        // swallows the per-row ids.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.workoutsToday")
    }

    private func toggle(_ row: WorkoutsTodayPresenter.Row) {
        Haptics.selection()
        withAnimation {
            if expandedRowIDs.contains(row.id) { expandedRowIDs.remove(row.id) }
            else { expandedRowIDs.insert(row.id) }
        }
    }
}

/// A planned workout: collapsed it reads like a completed row, expanded it shows
/// the prescription, the planned volume, its science, and a full-width start
/// action. It expands rather than navigates because there is no saved workout to
/// open yet — the plan only becomes a session once it is started.
struct HomePlannedWorkoutRow: View {
    let row: WorkoutsTodayPresenter.Row
    let isExpanded: Bool
    let onToggle: () -> Void
    let onStart: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) { header }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.today.row.\(row.sourceKey)")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded { expandedDetail }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: row.modality == .strength ? "calendar" : "heart.text.square")
                .font(.caption)
                .foregroundStyle(.teal)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.subheadline.weight(.medium))
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(row.status.badgeText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.teal)
                    .accessibilityIdentifier("home.today.badge.\(row.sourceKey)")
                Text(row.value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let why = row.why {
                Text(why).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(row.exercises) { exercise in
                HStack(spacing: 6) {
                    Text(exercise.name).font(.caption)
                    Spacer(minLength: 4)
                    Text("\(exercise.sets) × \(exercise.repsText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(loadText(exercise))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 52, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            if let volume = row.plannedVolumeKg {
                HStack {
                    Text("Planned volume").font(.caption.weight(.semibold))
                    Spacer()
                    Text(Format.weight(volume, unit: settings.unit, decimals: 0))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else if let minutes = row.targetMinutes, row.exercises.isEmpty {
                Text("About \(minutes) minutes").font(.caption).foregroundStyle(.secondary)
            }
            CoachSourcesLink(citationIds: row.citationIds,
                             identifier: "home.today.science.\(row.sourceKey)")
            CadenceActionButton(title: "Start This Workout",
                                systemImage: "play.fill",
                                action: onStart)
                .accessibilityIdentifier("home.today.start.\(row.sourceKey)")
        }
    }

    /// `BW` is a statement about the movement; a loaded lift with no resolvable
    /// load shows an em dash rather than inventing a number (decision D4).
    private func loadText(_ exercise: WorkoutsTodayPresenter.PlannedExerciseRow) -> String {
        if let load = exercise.loadKg, load > 0 {
            return Format.weight(load, unit: settings.unit, decimals: 0)
        }
        return exercise.isBodyweight ? "BW" : "—"
    }
}
