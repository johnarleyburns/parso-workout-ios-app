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

    static func make(sessions: [WorkoutSession], since: Date, now: Date,
                     performerKey: String = VolumeSummaryPerformer.ownerKey) -> [HomeMuscleHistory] {
        var buckets: [ExerciseKey: [HomeMuscleHistorySet]] = [:]

        for session in sessions where session.deletedAt == nil && session.date >= since && session.date <= now {
            for set in session.orderedSets where !set.isWarmup && set.reps > 0 {
                let key = set.isOwnerSet
                    ? VolumeSummaryPerformer.ownerKey
                    : set.performedBy?.id.uuidString ?? "unknown-partner"
                guard key == performerKey else { continue }
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
