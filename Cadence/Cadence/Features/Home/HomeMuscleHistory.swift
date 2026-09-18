import SwiftUI
import CadenceCore
import CadenceFeatures

struct HomeMuscleHistorySet: Identifiable, Equatable {
    let id: UUID
    let reps: Int
    let effectiveLoadKg: Double
    let addedLoadKg: Double
    let usesBodyweight: Bool
    let completedAt: Date
}

struct HomeMuscleHistoryExercise: Identifiable, Equatable {
    let id: String
    let name: String
    let isDirect: Bool
    let sets: [HomeMuscleHistorySet]
}

struct HomeMuscleHistory: Identifiable, Equatable {
    let group: MuscleGroup
    let displayName: String
    let creditedSets: Double
    let exercises: [HomeMuscleHistoryExercise]

    var id: MuscleGroup { group }
}

enum HomeMuscleHistoryPresenter {
    private struct ExerciseKey: Hashable {
        let group: MuscleGroup
        let exerciseID: UUID
        let exerciseName: String
        let isDirect: Bool
    }

    static func make(sessions: [WorkoutSession], since: Date, now: Date) -> [HomeMuscleHistory] {
        var buckets: [ExerciseKey: [HomeMuscleHistorySet]] = [:]

        for session in sessions where session.deletedAt == nil && session.date >= since && session.date <= now {
            for set in session.orderedSets where !set.isWarmup && set.isOwnerSet && set.reps > 0 {
                guard let exercise = set.exercise, exercise.volumeEligible else { continue }
                let direct = directGroups(for: exercise)
                let indirect = indirectGroups(for: exercise, excluding: direct)
                let detail = HomeMuscleHistorySet(
                    id: set.id,
                    reps: set.reps,
                    effectiveLoadKg: set.effectiveLoadKg,
                    addedLoadKg: set.weight,
                    usesBodyweight: set.usesBodyweight,
                    completedAt: set.completedAt)

                for group in direct {
                    let key = ExerciseKey(group: group, exerciseID: exercise.id,
                                          exerciseName: exercise.name, isDirect: true)
                    buckets[key, default: []].append(detail)
                }
                for group in indirect {
                    let key = ExerciseKey(group: group, exerciseID: exercise.id,
                                          exerciseName: exercise.name, isDirect: false)
                    buckets[key, default: []].append(detail)
                }
            }
        }

        return MuscleGroup.allCases.map { group in
            let entries = buckets
                .filter { $0.key.group == group }
                .map { key, sets in
                    HomeMuscleHistoryExercise(
                        id: "\(key.exerciseID.uuidString)-\(key.isDirect ? "direct" : "indirect")",
                        name: key.exerciseName,
                        isDirect: key.isDirect,
                        sets: sets.sorted {
                            if $0.completedAt != $1.completedAt {
                                return $0.completedAt < $1.completedAt
                            }
                            return $0.id.uuidString < $1.id.uuidString
                        })
                }
                .sorted {
                    if $0.isDirect != $1.isDirect { return $0.isDirect && !$1.isDirect }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            let credited = entries.reduce(0.0) { total, entry in
                total + Double(entry.sets.count) * (entry.isDirect ? 1.0 : 0.5)
            }
            return HomeMuscleHistory(group: group, displayName: group.displayName,
                                     creditedSets: credited, exercises: entries)
        }
    }

    private static func directGroups(for exercise: Exercise) -> Set<MuscleGroup> {
        let direct = exercise.directMuscles
        return Set(direct.isEmpty ? MuscleGroup.canonicalize(exercise.primaryMuscles) : direct)
    }

    private static func indirectGroups(for exercise: Exercise,
                                       excluding direct: Set<MuscleGroup>) -> Set<MuscleGroup> {
        let indirect = exercise.indirectMuscles
        let fallback = MuscleGroup.canonicalize(exercise.secondaryMuscles)
        return Set(indirect.isEmpty ? fallback : indirect).subtracting(direct)
    }
}

struct HomeMuscleMapView: View {
    let dashboard: HomeDashboardState
    let onSelect: (MuscleGroup) -> Void
    let onOpenCardio: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Muscle map")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            HStack(alignment: .top, spacing: 6) {
                calloutPanel(.front, title: "FRONT")
                calloutPanel(.back, title: "BACK")
            }
            Button(action: onOpenCardio) {
                Label("Cardio · \(Int(dashboard.cardioDetail.moderateEquivalentMinutes.rounded())) min",
                      systemImage: "heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cardio, \(Int(dashboard.cardioDetail.moderateEquivalentMinutes.rounded())) minutes this week")
            Text("Tap a highlighted muscle for this week's direct and indirect work")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func calloutPanel(_ panel: MuscleMapPanel, title: String) -> some View {
        MuscleMapSideView(
            panel: panel,
            title: title,
            callouts: MuscleMapLayout.callouts(for: panel),
            setsLabel: setsLabel(for:),
            statusColor: statusColor(for:),
            onSelect: onSelect)
    }

    private func regionLabel(for group: MuscleGroup) -> String {
        "\(group.displayName)\n\(setsLabel(for: group))"
    }

    private func setsLabel(for group: MuscleGroup) -> String {
        let sets = dashboard.volume.first(where: { $0.group == group })?.sets ?? 0
        return "\(WeeklySetProgress.formattedSets(sets))/12"
    }

    private func statusColor(for group: MuscleGroup) -> Color {
        guard let row = dashboard.volume.first(where: { $0.group == group }) else { return .blue }
        switch row.zone {
        case .belowMinimum: return .blue
        case .building: return .yellow
        case .productive: return .green
        case .aboveMaximum: return .red
        }
    }
}

private struct MuscleMapSideView: View {
    let panel: MuscleMapPanel
    let title: String
    let callouts: [MuscleMapCallout]
    let setsLabel: (MuscleGroup) -> String
    let statusColor: (MuscleGroup) -> Color
    let onSelect: (MuscleGroup) -> Void

    private let labelWidth: CGFloat = 70
    private let imageWidth: CGFloat = 92
    private let rowHeight: CGFloat = 44
    private let rowSpacing: CGFloat = 3

    private var imageHeight: CGFloat { imageWidth / CGFloat(MuscleMapLayout.halfRatio) }
    private var contentHeight: CGFloat {
        max(imageHeight, CGFloat(callouts.count) * rowHeight + CGFloat(max(0, callouts.count - 1)) * rowSpacing)
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: panel == .front ? .trailing : .leading)
            ZStack {
                HStack(spacing: 4) {
                    if panel == .back { image }
                    calloutColumn
                    if panel == .front { image }
                }
                connectorLines
            }
            .frame(height: contentHeight)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title.lowercased()) muscle map")
    }

    private var calloutColumn: some View {
        VStack(spacing: rowSpacing) {
            ForEach(callouts) { callout in
                Button {
                    onSelect(callout.group)
                } label: {
                    Text("\(callout.group.displayName)\n\(setsLabel(callout.group))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(panel == .front ? .trailing : .leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: panel == .front ? .trailing : .leading)
                        .padding(.horizontal, 4)
                        .background(statusColor(callout.group).opacity(0.20),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(statusColor(callout.group).opacity(0.65), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .frame(width: labelWidth, height: rowHeight)
                .contentShape(Rectangle())
                .accessibilityLabel("\(callout.group.displayName), \(setsLabel(callout.group)) this week")
                .accessibilityHint("Shows direct and indirect exercise history")
                .accessibilityIdentifier("home.week.muscle.\(callout.panel.rawValue).\(callout.group.rawValue)")
            }
        }
    }

    private var image: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.04)
            Image("MusclesFrontBack")
                .resizable()
                .frame(width: imageWidth * 2, height: imageHeight)
                .offset(x: panel == .front ? 0 : -imageWidth)
                .accessibilityHidden(true)
            ForEach(callouts) { callout in
                Button {
                    onSelect(callout.group)
                } label: {
                    Circle()
                        .fill(statusColor(callout.group).opacity(0.88))
                        .overlay { Circle().stroke(.white, lineWidth: 1.5) }
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .position(x: CGFloat(callout.anchorX) * imageWidth,
                          y: CGFloat(callout.anchorY) * imageHeight)
                .accessibilityLabel("\(callout.group.displayName), \(setsLabel(callout.group)) this week")
                .accessibilityHint("Shows direct and indirect exercise history")
                .accessibilityIdentifier("home.week.muscle.region.\(callout.panel.rawValue).\(callout.group.rawValue)")
            }
        }
        .frame(width: imageWidth, height: imageHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipped()
    }

    private var connectorLines: some View {
        Canvas { context, size in
            let imageOriginX: CGFloat = panel == .front ? labelWidth + 4 : 0
            let imageOriginY = (contentHeight - imageHeight) / 2
                for (index, callout) in callouts.enumerated() {
                let rowY = CGFloat(index) * (rowHeight + rowSpacing) + rowHeight / 2
                let anchorX = imageOriginX + CGFloat(callout.anchorX) * imageWidth
                let anchorY = imageOriginY + CGFloat(callout.anchorY) * imageHeight
                let startX = panel == .front ? labelWidth : imageWidth
                var path = Path()
                path.move(to: CGPoint(x: startX, y: rowY))
                path.addLine(to: CGPoint(x: anchorX, y: anchorY))
                context.stroke(path,
                               with: .color(statusColor(callout.group).opacity(0.75)),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: anchorX - 2, y: anchorY - 2,
                                                     width: 4, height: 4)),
                              with: .color(statusColor(callout.group)))
            }
        }
        .allowsHitTesting(false)
        .frame(width: labelWidth + imageWidth + 4, height: contentHeight)
    }
}

struct HomeMuscleDetailSheet: View {
    let history: HomeMuscleHistory
    let unit: MeasurementUnitPreference
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(history.displayName).font(.title3.weight(.bold))
                            Text("\(WeeklySetProgress.formattedSets(history.creditedSets)) credited sets this week")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(WeeklySetProgress.zone(for: history.creditedSets).displayText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    if history.exercises.isEmpty {
                        ContentUnavailableView("No logged work yet", systemImage: "figure.strengthtraining.traditional",
                                               description: Text("Working sets for this muscle will appear here during the current week."))
                    } else {
                        Text("This week's exercises")
                            .font(.headline)
                        ForEach(history.exercises) { exercise in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(exercise.name).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(exercise.isDirect ? "Direct" : "Indirect")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(exercise.isDirect ? .green : .secondary)
                                }
                                Text("\(exercise.sets.count) sets · \(repsLabel(exercise.sets)) · \(loadLabel(exercise.sets))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(exercise.sets.map { set in
                                    "\(set.reps) reps @ \(loadLabel(set))"
                                }.joined(separator: "  ·  "))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Weekly muscle detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func repsLabel(_ sets: [HomeMuscleHistorySet]) -> String {
        sets.map { String($0.reps) }.joined(separator: "/") + " reps"
    }

    private func loadLabel(_ sets: [HomeMuscleHistorySet]) -> String {
        sets.map(loadLabel).joined(separator: "/")
    }

    private func loadLabel(_ set: HomeMuscleHistorySet) -> String {
        if set.usesBodyweight {
            return set.addedLoadKg > 0
                ? "BW + \(Format.weightValue(set.addedLoadKg, unit: unit, decimals: 1))"
                : "BW"
        }
        return Format.weightValue(set.effectiveLoadKg, unit: unit, decimals: 1)
    }
}
