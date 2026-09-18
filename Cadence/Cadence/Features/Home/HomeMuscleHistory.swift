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

private struct HomeMuscleMapRegion: Identifiable {
    enum Side { case front, back }

    let group: MuscleGroup
    let side: Side
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var id: String { "\(side)-\(group.rawValue)" }

    var sideName: String {
        switch side {
        case .front: "front"
        case .back: "back"
        }
    }
}

struct HomeMuscleMapView: View {
    let dashboard: HomeDashboardState
    let onSelect: (MuscleGroup) -> Void
    let onOpenCardio: () -> Void

    private static let sourceRatio: CGFloat = 406.99026 / 354.43411
    private static let halfRatio: CGFloat = 203.49526 / 354.43411
    private static let regions: [HomeMuscleMapRegion] = [
        .init(group: .chest, side: .front, x: 0.50, y: 0.32, width: 0.56, height: 0.13),
        .init(group: .shoulders, side: .front, x: 0.27, y: 0.25, width: 0.34, height: 0.11),
        .init(group: .quadriceps, side: .front, x: 0.50, y: 0.61, width: 0.62, height: 0.20),
        .init(group: .lats, side: .back, x: 0.50, y: 0.33, width: 0.65, height: 0.18),
        .init(group: .glutes, side: .back, x: 0.50, y: 0.53, width: 0.58, height: 0.13),
        .init(group: .hamstrings, side: .back, x: 0.50, y: 0.68, width: 0.62, height: 0.19)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Muscle map")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            HStack(alignment: .top, spacing: 6) {
                panel(side: .front, title: "FRONT")
                panel(side: .back, title: "BACK")
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

    private func panel(side: HomeMuscleMapRegion.Side, title: String) -> some View {
        GeometryReader { proxy in
            let imageHeight = proxy.size.height
            let imageWidth = imageHeight * Self.sourceRatio
            let imageX = side == .front ? 0 : proxy.size.width - imageWidth
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.04)
                Image("MusclesFrontBack")
                    .resizable()
                    .frame(width: imageWidth, height: imageHeight)
                    .offset(x: imageX)
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                ForEach(Self.regions.filter { $0.side == side }) { region in
                    Button {
                        onSelect(region.group)
                    } label: {
                        Text(regionLabel(for: region.group))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(statusColor(for: region.group).opacity(0.78),
                                        in: RoundedRectangle(cornerRadius: 7))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(.white.opacity(0.75), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(width: proxy.size.width * region.width,
                           height: proxy.size.height * region.height)
                    .position(x: proxy.size.width * region.x,
                              y: proxy.size.height * region.y)
                    .accessibilityLabel("\(region.group.displayName), \(setsLabel(for: region.group)) this week")
                    .accessibilityHint("Shows direct and indirect exercise history")
                    .accessibilityIdentifier("home.week.muscle.\(region.sideName).\(region.group.rawValue)")
                }
            }
            .clipped()
        }
        .aspectRatio(Self.halfRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("\(title.lowercased()) muscle map")
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
