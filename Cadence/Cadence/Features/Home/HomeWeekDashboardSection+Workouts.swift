import SwiftUI
import CadenceCore
import CadenceFeatures

extension HomeWeekDashboardSection {
    func activityDose(_ dose: WeeklyActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activity Dose")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
            HStack {
                Text("Actual activity")
                Spacer()
                Text("\(Int(dose.actualActivityMinutes.rounded())) min")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Text("Standard MET-minutes")
                Spacer()
                Text("\(Int(dose.totalStandardMETMinutes.rounded()))")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            if let citation = CitationRegistry.citation(forId: "compendium2024AdultPhysicalActivities") {
                CitationLink(citation: citation,
                             context: "MET-minutes are a separate standardized activity-dose estimate; they are not a replacement for cardio guideline credit.",
                             compact: true)
            }
        }
        .font(.caption)
        .accessibilityIdentifier("home.week.activityDose")
    }

    var myWorkoutsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if plannedItems.isEmpty && inProgressSessions.isEmpty && completedEntries.isEmpty {
                Text("No workouts this week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(plannedItems) { item in
                Button { Haptics.selection(); onOpenPlanned(item.id) } label: {
                    myWorkoutRow(title: item.title, detail: item.detail, badge: "PLANNED", badgeTint: .teal)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows workout details")
                .accessibilityIdentifier("home.week.planned.\(item.id.uuidString)")
            }
            ForEach(inProgressSessions, id: \.id) { session in
                Button { onResumeWorkout(session) } label: {
                    myWorkoutRow(title: session.title.isEmpty ? String(localized: "Strength session") : session.title,
                                 detail: String(localized: "\(session.orderedSets.count) sets logged"),
                                 badge: "IN PROGRESS", badgeTint: .orange)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Resumes the workout")
                .accessibilityIdentifier("home.week.inProgress.\(session.id.uuidString)")
            }
            ForEach(completedEntries) { entry in
                HomeWeekWorkoutRow(entry: entry) { onOpenWorkout(entry) }
            }
        }
        .accessibilityIdentifier("home.week.group.myworkouts")
    }

    func myWorkoutRow(title: String, detail: String, badge: String, badgeTint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar").font(.caption).foregroundStyle(badgeTint)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(badge).font(.caption2.weight(.bold)).foregroundStyle(badgeTint)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
