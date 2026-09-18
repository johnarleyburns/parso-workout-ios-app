import SwiftUI
import CadenceCore
import CadenceFeatures

// MARK: - Session banners
//
// Plain markup lifted out of `SessionView` to keep that file shrinking under the
// test-pyramid ratchet. No logic lives here; every value comes from the session
// or from `SessionViewModel`.

extension SessionView {
    func planBanner(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.schemeSummary).font(.headline)
                .accessibilityIdentifier("session.planBanner")
            if let notes = plan.notes {
                Text(notes).font(.caption).foregroundStyle(.secondary)
            }
            supersetSummary
        }
        .padding(CGFloat(LayoutMetrics.cardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .accentColor)
    }

    @ViewBuilder
    private var supersetSummary: some View {
        let groups = Dictionary(grouping: session.plannedPrescriptions.compactMap { prescription -> (String, String)? in
            guard let group = prescription.supersetGroup, !group.isEmpty else { return nil }
            return (group, prescription.exerciseName)
        }, by: \.0)
        if !groups.isEmpty {
            ForEach(groups.keys.sorted(), id: \.self) { group in
                let names = groups[group, default: []].map(\.1).joined(separator: " + ")
                Label("Superset \(group): \(names)", systemImage: "link")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("session.superset.\(group)")
            }
        }
    }

    var loggedDateBanner: some View {
        Button { datePickerPresented = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                Text("Logging \(session.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "calendar").font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("log.dateBanner")
    }

    var editableMetadataRow: some View {
        HStack(spacing: 16) {
            Button { datePickerPresented = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.caption)
                    Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                }.foregroundStyle(.tint)
            }
            .buttonStyle(.plain).accessibilityIdentifier("session.editDate")
            if session.endedAt != nil {
                Button { endDatePickerPresented = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.caption)
                        if let end = session.endedAt {
                            Text(Format.duration(end.timeIntervalSince(session.date))).font(.subheadline)
                        }
                    }.foregroundStyle(.tint)
                }
                .buttonStyle(.plain).accessibilityIdentifier("session.editEndTime")
            }
            Spacer()
        }
    }
}
